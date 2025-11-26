-- Get T-Level student and set as parameter
DECLARE @student_id NUMERIC(16,0);

-- Start with L6 student
SELECT @student_id = s_id
FROM capd_student 
WHERE s_studentreference = '0056741';

-- CTE contains students that are current or applicants and have a periodic in the current year
-- Applicants ?
WITH students AS (
	SELECT st.student_id
	, sess.ay_startyear
	, sess.yr_session_id
	, st.student_reference
	, st.category
	, st.title
	, st.surname
	, st.first_name
	, st.preferred_name
	, st.nationality_description
	, st.pd_uniquelearnerno
	, SUBSTRING(st.ethnicity_description,6,LEN(st.ethnicity_description) - 5) EthnicOrigin
	, gender_code.vc_name StudentGender
	, gender_exp.vc_name StudentPreferredGender
	, st.previous_school PreviousSchoolName
	, st.dob DateOfBirth
	, rhc.getAgeAtDate(st.dob,GETDATE()) Age -- Call function to get their Age	
	FROM mis.academic_year_sessions sess
	INNER JOIN capd_studentperiodicilr per
		ON sess.ay_startyear = per.spi_academicyear
		AND sess.yr_session_id = per.spi_session
	INNER JOIN mis.v_student_details st
		ON per.spi_student = st.student_id
		AND st.category NOT IN ('IAP', 'TEST', 'APR', 'BDU', 'PRO')
		AND st.student_status IN ('0','1')
	LEFT JOIN caps_valid_codes gender_code 
		ON st.gender = gender_code.vc_code
		AND gender_code.vc_domain = 'gender'
	LEFT JOIN caps_valid_codes gender_exp
		ON st.gender_expression = gender_exp.vc_code
		AND gender_exp.vc_domain = 'genderexpression'
	WHERE sess.cy_offset = 0
	AND sess.ht_half_term = 'AU1' 
	AND st.student_id = @student_id
	)
-- CTE Addapp contains the details from the relevant student custom record
, addapp AS (
	SELECT aa.sc_id aa_custom_id
	, st.student_id 
	, IIF(aa.sc_reference1 = 'Y','Yes','No') UKResidency
	, IIF(aa.sc_reference2 = 'Y','Yes','No') OutsideUK
	, IIF(aa.sc_reference3 = 'Y','Yes','No') VisaRestrict
	, IIF(aa.sc_number1 = -1,'Y','N') EHCP
	, code1_code.vc_name [Custom Code 1]
	, code5_code.vc_name [Custom Code 5]
	, code6_code.vc_name [Custom Code 6]
	, code7_code.vc_name [Custom Code 7]
	, code8_code.vc_name [Custom Code 8]
	FROM capd_studentcustom aa
	INNER JOIN students st
		ON aa.sc_customstudent = st.student_id
	LEFT JOIN caps_valid_codes code1_code
		ON aa.sc_code1 = code1_code.vc_code
		AND code1_code.vc_domain = 'studentcode1'
	LEFT JOIN caps_valid_codes code5_code 
		ON aa.sc_code5 = code5_code.vc_code 
		AND code5_code.vc_domain = 'studentcode5'
	LEFT JOIN caps_valid_codes code6_code 
		ON aa.sc_code6 = code6_code.vc_code 
		AND code6_code.vc_domain = 'studentcode6'
	LEFT JOIN caps_valid_codes code7_code 
		ON aa.sc_code7 = code7_code.vc_code 
		AND code7_code.vc_domain = 'studentcode7'
	LEFT JOIN caps_valid_codes code8_code 
		ON aa.sc_code8 = code8_code.vc_code 
		AND code8_code.vc_domain = 'studentcode8'
	WHERE aa.sc_type = 'AddApp'
	)
-- CTE to Calculate the number of days at the address either using the start date or the date the address was first inserted to the system (from the audit trail)
, time_at_address AS (
	SELECT st.student_id
	, addr.a_name
	, addr.a_reference
	, MAX(DATEDIFF(DD,CONVERT(DATE,COALESCE(addr.a_start,aud.SAT_START)),GETDATE())) days_at_address
	FROM capd_person pers
	INNER JOIN students st
		ON pers.p_id = st.student_id
	INNER JOIN capd_address addr
		ON pers.p_personaddress = addr.a_id
		AND COALESCE(addr.a_end,getdate()) >= getdate()
	LEFT JOIN CAPS_SYSTEM_AUDIT_TRAIL aud
		ON addr.a_id = aud.SAT_ID
		AND aud.SAT_ACTION = 'insert'
	GROUP BY st.student_id
	, addr.a_name
	, addr.a_reference )
, first_date_started AS (
	SELECT st.s_id student_id
	, MIN(sess.ay_startyear) from_year
	FROM capd_moduleenrolment enrol
	INNER JOIN capd_student st
		ON enrol.e_student = st.s_id
	INNER JOIN mis.academic_year_sessions sess
		ON enrol.e_start BETWEEN sess.ay_start AND sess.ay_end
		AND sess.ht_half_term = 'AU1'
	WHERE enrol.e_status = '1'
	AND enrol.e_type = 'PR'
	GROUP BY st.s_id
	)
-- CTE for Students enrolment details 
, enrolments AS (
	SELECT cs_en.e_student student_id
	, pr.m_id prog_id
	, pr.m_reference prog_ref
	, pr.m_name prog_name
	, pr.m_start prog_start
	, pr.m_end prog_end
	, pr_en_isr.ei_q17 planned_end
	, pr_en_isr.ei_q18m06 prog_actual_end
	, cs.m_id course_id
	, cs.m_reference course_ref
	, cs.m_name course_name
	, cs.m_start course_start
	, cs.m_end course_end
	, cs_en.e_reason reason_for_fee_change
	, pr_lars.lld_awardorgcode learning_aim_award_code
	, COALESCE(pr.m_name,cs.m_name) module_name
	, IIF(pr_lars.lld_learnaimref IS NOT NULL,cs.m_name,COALESCE(cs_lars.lld_learnaimreftitle,cs.m_name)) learning_aim_title
	, COALESCE(pr_lars.lld_learnaimref,cs_lars.lld_learnaimref) learning_aim_ref
	, CASE WHEN pr_en.e_level = 'TL' THEN 
			CONVERT(INT,COALESCE(en_per.epi_offthejobtraininghrs,0)) 
		ELSE
			CONVERT(INT,COALESCE(cs_isr.mi_ilrplanlearnhours,0)) 
		END planned_learning_hours
	, CASE WHEN pr_en.e_level = 'TL' THEN 
			IIF(
				pr_yr.ay_startyear = current_year.ay_startyear
				,CONVERT(INT,COALESCE(en_per.epi_offthejobtraininghrs,0)) 
				,0
			)
		ELSE
			CONVERT(INT,IIF(COALESCE(pr_isr.mi_planlearnhoursyear1,0) > 0,pr_isr.mi_planlearnhoursyear1,COALESCE(cs_isr.mi_planlearnhoursyear1,0))) 
		END planned_learning_hours_y1
	, CASE WHEN pr_en.e_level = 'TL' THEN 
			IIF(
				pr_yr.ay_startyear < current_year.ay_startyear
				,CONVERT(INT,COALESCE(en_per.epi_offthejobtraininghrs,0)) 
				,0
			)
		ELSE
			CONVERT(INT,IIF(COALESCE(pr_isr.mi_planlearnhoursyear2,0) > 0,pr_isr.mi_planlearnhoursyear2,COALESCE(cs_isr.mi_planlearnhoursyear2,0))) 
		END planned_learning_hours_y2
	, CONVERT(INT,COALESCE(pr_isr.mi_ilrplaneephours,0)) planned_eep_hours
	, CONVERT(INT,IIF(COALESCE(pr_isr.mi_planothhoursyear1,0) > 0,pr_isr.mi_planothhoursyear1,COALESCE(cs_isr.mi_planothhoursyear1,0))) planned_other_hours_y1
	, CONVERT(INT,IIF(COALESCE(pr_isr.mi_planothhoursyear2,0) > 0,pr_isr.mi_planothhoursyear2,COALESCE(cs_isr.mi_planothhoursyear2,0))) planned_other_hours_y2
	, DATEDIFF(DAY,cs_en.e_start,cs_en.e_end) enrolment_days
	, sess.s_academicyear ay_startyear
	, sess.s_id yr_session_id
	, sess.s_academicyear academic_year
	, pr_yr.ay_startyear pr_startyear
	FROM capd_moduleenrolment cs_en
	CROSS JOIN mis.academic_year_sessions as current_year
	INNER JOIN capd_module cs
		ON cs_en.e_module = cs.m_id
	LEFT JOIN capd_moduleisr cs_isr
		ON cs.m_id = cs_isr.mi_id
	LEFT JOIN capd_enrolmentisr cs_en_isr
		ON cs_en.e_id = cs_en_isr.ei_id
	LEFT JOIN capd_larslearningdelivery cs_lars
		ON cs_en_isr.ei_q02m02 = cs_lars.lld_learnaimref
	INNER JOIN capd_moduleenrolment pr_en
		ON cs_en.e_parent = pr_en.e_id
		AND (pr_en.e_status = '1'
			OR ( pr_en.e_status = '2'
			AND pr_en.e_start BETWEEN current_year.ay_start AND current_year.ay_end -- Status 1 is Current, and 2 is completed
			)
		)
		AND pr_en.e_type = 'PR'
	INNER JOIN mis.academic_year_sessions pr_yr
		ON pr_en.e_start BETWEEN pr_yr.ay_start AND pr_yr.ay_end
		AND pr_yr.ht_half_term = 'AU1'
	-- For T-Levels the planned hours are on the enrolment periodic type "PH" these all go into Year 1
	LEFT JOIN capd_enrolmentperiodicilr en_per
		ON pr_en.e_id = en_per.epi_enrolment
		AND en_per.epi_type = 'PH'
		AND en_per.epi_start BETWEEN current_year.ay_start AND current_year.ay_end
		AND pr_en.e_level = 'TL'
	INNER JOIN capd_module pr
		ON pr_en.e_module = pr.m_id
	LEFT JOIN capd_enrolmentisr pr_en_isr
		ON pr_en.e_id = pr_en_isr.ei_id
	LEFT JOIN capd_larslearningdelivery pr_lars
		ON pr_en_isr.ei_q02m02 = pr_lars.lld_learnaimref
	LEFT JOIN capd_moduleisr pr_isr
		ON pr.m_id = pr_isr.mi_id
	LEFT JOIN capd_session sess
		ON cs.m_modulesession = sess.s_id
	WHERE current_year.cy_offset = 0 
	AND current_year.ht_half_term = 'AU1' 
	AND cs_en.e_type = 'CS'
	AND (
		cs_en.e_status = '1' 
		OR ( cs_en.e_status = '2'
			AND cs_en.e_start BETWEEN current_year.ay_start AND current_year.ay_end
			
			)
		)
	-- If the program is a T-Level only get the course that has a main aim of 5
	AND (pr_en.e_level <> 'TL'
		OR (
			pr_en.e_level = 'TL'
			AND COALESCE(cs_en_isr.ei_ilraimtype,'0') = '5'
			)
		)
		
	) 
SELECT st.student_id StudentID
, st.ay_startyear AcademicYear
, start_yr.from_year startYear
, en.pr_startyear prog_start_year
, st.yr_session_id SessionId
, st.student_reference StudentReference
, st.category StudentCategory
, st.title Title
, st.surname StudentSurname
, st.first_name StudentForenames
, st.preferred_name StudentPreferredName
, st.nationality_description StudentNationality
, st.pd_uniquelearnerno ULN
, st.EthnicOrigin
, st.StudentGender
, st.StudentPreferredGender
, st.PreviousSchoolName
, st.DateOfBirth
, st.Age
, addapp.UKResidency
, addapp.OutsideUK
, addapp.VisaRestrict
, addapp.EHCP
, addapp.[Custom Code 1]
, addapp.[Custom Code 5]
, addapp.[Custom Code 6]
, addapp.[Custom Code 7]
, addapp.[Custom Code 8]
, taa.days_at_address [TimeAtAddress]
, st.preferred_name + ' ' + st.surname + ' (' + st.student_reference + ')' StudentLabel
, ISNULL(un_st.s_criminalconvflag, 0) ConvictionFlag
, ISNULL(un_st.s_criminalconv, '') ConvictionDate
, addr.student_address StudentAddress
, addr.student_postcode StudentPostcode
, addr.email_address StudentCollegeEmail
, addr.home_email_address StudentEmailAddress
, addr.mobile_number StudentMobileNumber
, addr.student_home_phone StudentHomeNumber
, nok.nok_relationship NOK1_Relation
, nok.nok_first_name + ' ' + nok.nok_surname NOK1_Name
, nok.nok_email NOK1_EmailAddress
, nok.nok_phone NOK1_Number
, nok.nok_address NOK1_PostalAddress
, nok.nok_postcode NOK1_Postcode
, nok.nok2_relationship NOK2_Relation
, nok.nok2_first_name + ' ' + nok.nok2_surname NOK2_Name
, nok.nok2_email NOK2_EmailAddress
, nok.nok2_phone NOK2_Number
, nok.nok2_address NOK2_PostalAddress
, nok.nok2_postcode NOK2_Postcode
, en.learning_aim_award_code LearningAimAwardingOrganisationCode
, en.learning_aim_title LearningAimTitle
, en.learning_aim_ref A09Q02M02LearningAimReference
, en.module_name ModuleName
, en.prog_id ProgrammeId
, en.prog_name ProgrammeModuleName
, en.prog_ref ProgrammeModuleReference
, en.prog_start ProgrammeStart
, en.prog_end ProgrammeEnd
, en.prog_actual_end ProgActualEnd
, en.course_id CourseId
, en.course_name CourseModuleName
, en.course_ref CourseModuleReference
, en.course_start CourseStart
, en.course_end CourseEnd
, en.planned_learning_hours ILRPlannedLearningHours
, en.planned_learning_hours_y1 PLHYear1
, en.planned_learning_hours_y2 PLHYear2
, en.planned_eep_hours ILRPlannedEmployabilityEnrichmentAndPastoralHours
, en.planned_other_hours_y1 EEPHoursYear1
, en.planned_other_hours_y2 EEPHoursYear2
, app.sa_id ApplicationId
, app.sa_reference ApplicationReference
, NULL EnrolmentStaffId
, NULL EnrolmentStaffReference 
, st.ay_startyear
, start_yr.from_year

,
	CASE
		WHEN st.ay_startyear = start_yr.from_year THEN 'Y1'
		WHEN st.ay_startyear - start_yr.from_year = 1 THEN 'Y2'
		WHEN st.ay_startyear - start_yr.from_year = 2 THEN 'Y3'
		ELSE '>3'
	END AS StudentYear
,
	CASE 
		WHEN st.ay_startyear = start_yr.from_year  THEN en.planned_learning_hours_y1
		WHEN start_yr.from_year = en.pr_startyear THEN en.planned_learning_hours_y1
		WHEN st.ay_startyear != start_yr.from_year THEN 0
	END AS adj_PLH1
,

	CASE
		WHEN st.ay_startyear = start_yr.from_year  THEN en.planned_learning_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 1 THEN en.planned_learning_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 2 AND st.ay_startyear - en.pr_startyear = 1 THEN en.planned_learning_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 2 AND st.ay_startyear - en.pr_startyear = 2 THEN en.planned_learning_hours_y2
		ELSE '0'
	END AS adj_PLH2
,

	CASE
		
		WHEN st.ay_startyear - start_yr.from_year = 2 THEN en.planned_learning_hours_y2
		ELSE '0'
	END AS adj_PLH3
-- st.ay_startyear is the current year
-- start_yr.from_year is the year they started at the college on any program they are enrolled on
-- en.pr_startyear is the program start year

-- If the student started this year - year one
-- If the student started last year - year two 
-- If the student started 2 years ago - year 3
, IIF(st.ay_startyear = start_yr.from_year, en.planned_other_hours_y1, 0) 	 adj_EEP1
, IIF(st.ay_startyear - 1 = start_yr.from_year 
	AND st.ay_startyear = en.pr_startyear, en.planned_other_hours_y1, 0) 	 adj_EEP2
, IIF(st.ay_startyear - 2 = start_yr.from_year, en.planned_other_hours_y2, 0) 	 adj_EEP3

, CASE 
		WHEN st.ay_startyear = start_yr.from_year  THEN en.planned_other_hours_y1
		WHEN start_yr.from_year = en.pr_startyear THEN en.planned_other_hours_y1
		WHEN st.ay_startyear != start_yr.from_year THEN 0
	END AS adj_EEP1
,
	CASE
		WHEN st.ay_startyear = start_yr.from_year  THEN en.planned_other_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 1 THEN en.planned_other_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 2 AND st.ay_startyear - en.pr_startyear = 1 THEN en.planned_other_hours_y2
		WHEN st.ay_startyear - start_yr.from_year = 2 AND st.ay_startyear - en.pr_startyear = 2 THEN en.planned_other_hours_y2
		ELSE '0'
	END AS adj_EEP2
,
	CASE
		WHEN st.ay_startyear - start_yr.from_year = 2 THEN en.planned_other_hours_y2
		ELSE '0'
	END AS adj_EEP3
FROM students st
INNER JOIN capd_student un_st
	ON st.student_id = un_st.s_id
INNER JOIN first_date_started start_yr
	ON st.student_id = start_yr.student_id
LEFT JOIN addapp 
	ON st.student_id = addapp.student_id
LEFT JOIN time_at_address taa
	ON st.student_id = taa.student_id
LEFT JOIN mis.v_student_addresses addr
	ON st.student_id = addr.student_id
LEFT JOIN mis.v_student_nok_details nok
	ON st.student_id = nok.student_id
LEFT JOIN enrolments en
	ON st.student_id = en.student_id
LEFT JOIN capd_studentapplication app
	ON st.student_id = app.sa_student
	AND app.sa_reference LIKE rhc.AppYearRef();
