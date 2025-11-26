-- Teachers
WITH teachers AS (
	SELECT a_staff staff_id
	FROM capd_appointment 
	WHERE COALESCE(a_end,getdate()) >= getdate()
	AND a_grade = 'TE'
	GROUP BY a_staff
	) 
SELECT tch.staff_id
, cl.m_reference
, pr.year_of_program
, cl.m_level class_level
, levs.level_group
, act.a_id activity_id
, act.a_start
, act.a_end
, act.a_name
, act.a_weekpattern
FROM mis.academic_year_sessions sess
INNER JOIN capd_activity act
	ON act.a_start BETWEEN sess.ay_start AND sess.ay_end
	AND COALESCE(act.a_end,getdate()) >=getdate()
INNER JOIN capd_staffactivity sa
	ON act.a_id = sa.sa_activity
INNER JOIN teachers tch
	ON sa.sa_activitystaff = tch.staff_id
LEFT JOIN capd_moduleactivity ma
	ON act.a_id = ma.ma_activity
LEFT JOIN capd_module cl
	ON ma.ma_activitymodule = cl.m_id
LEFT JOIN mis.level_codes levs
	ON cl.m_level = levs.level_code
LEFT JOIN mis.v_class_course_program_structure pr
	ON cl.m_id = pr.class_id
WHERE sess.cy_offset = 0
AND sess.ht_half_term = 'AU1'
;
