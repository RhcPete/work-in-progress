ALTER PROCEDURE [pbi].[sp_populate_ru_teacher_activity] AS
BEGIN
	DECLARE @academic_year INT;
	DECLARE @year_start DATETIME;
	SELECT @academic_year = ay_startyear
	, @year_start = ay_start
	FROM mis.academic_year_sessions
	WHERE cy_offset = 0
	AND ht_half_term = 'AU1';

	-- Get current week number
	DECLARE @start_of_week DATE;
	SELECT  @start_of_week = start_of_week
	FROM mis.attendance_calendar 
	WHERE attendance_date = CONVERT(DATE,getdate());

	-- Need the earliest and latest dates of interest
	DECLARE @from_date DATETIME;
	DECLARE @to_date DATETIME;
	SELECT @from_date = CONVERT(DATETIME,MIN(calendar_date))
	, @to_date = CONVERT(DATETIME,MAX(calendar_date))
	FROM pbi.ru_timeslots
	WHERE start_of_week > @start_of_week;

	DECLARE @activity_times AS TABLE 
		( activity_id NUMERIC(16,0) NOT NULL
		, staff_id NUMERIC(16,0) NOT NULL 
		, activity_time DATETIME NOT NULL
		, activity_end DATETIME NOT NULL
		, no_of_students INT NULL
		, PRIMARY KEY (activity_id ASC, staff_id, activity_time ASC)
		);

	-- Activities for staff that are in progress
	INSERT INTO @activity_times
		( activity_id
		, staff_id
		, activity_time 
		, activity_end )
	SELECT act.a_id
	, stf.s_id 
	, wp.mapped_date
	, CONVERT(DATETIME,CONVERT(DATE,wp.mapped_date)) + CONVERT(VARCHAR(5),CONVERT(TIME,wp.actual_end)) mapped_end
	FROM capd_activity act
	INNER JOIN mis.weekpattern_date_map_for_everything(@academic_year) wp
		ON act.a_start = wp.actual_date
		AND act.a_end = wp.actual_end
		AND act.a_weekpattern = wp.week_pattern
	INNER JOIN capd_staffactivity sa
		ON act.a_id = sa.sa_activity
	INNER JOIN capd_staff stf
		ON sa.sa_activitystaff= stf.s_id
	WHERE act.a_start > @year_start
	AND act.a_end > @from_date
	AND act.a_start <= @to_date;

	-- Activity size (count of students)
	DECLARE @activity_size TABLE 
		( activity_id NUMERIC(16,0) NOT NULL PRIMARY KEY
		, no_of_students INT );
	WITH activities AS 
		( SELECT att.activity_id
		FROM @activity_times att
		GROUP BY att.activity_id
		)
	INSERT INTO @activity_size
	SELECT act.activity_id
	, COUNT(DISTINCT en.e_student) no_of_students
	FROM activities act
	INNER JOIN capd_moduleactivity ma
		ON act.activity_id = ma.ma_activity
	INNER JOIN capd_module cl
		ON ma.ma_activitymodule = cl.m_id
	INNER JOIN capd_moduleenrolment en
		ON cl.m_id = en.e_module
		AND en.e_status = '1'
	GROUP BY act.activity_id
	, cl.m_id
	, cl.m_reference
	, cl.m_name
	;

	UPDATE old
	SET old.no_of_students = new.no_of_students
	FROM @activity_times old
	INNER JOIN @activity_size new
		ON old.activity_id = new.activity_id
	;

	-- Final query inserts to teacher activity PBI table
	TRUNCATE TABLE pbi.ru_teacher_activity;
	INSERT INTO pbi.ru_teacher_activity
           ( date_key
           , week_number
           , calendar_date
           , lesson_num
           , day_of_week
           , activity_id
           , staff_id
           , no_of_students
           , preferred_name
           , surname
           , staff_reference
           , from_time
           , to_time
           , activity_name
           , activity_ref
           , module_id
           , detls )
    SELECT CONVERT(VARCHAR(20), sa.sa_id) 
		+ '_' + CONVERT(VARCHAR(20),CONVERT(BIGINT,CONVERT(DATETIME,ts.calendar_date)))
		+ '_' + CONVERT(VARCHAR,ts.lesson_num) date_key
	, ts.week_number
	, ts.calendar_date
	, ts.lesson_num
	, ts.day_of_week
	, att.activity_id
	, att.staff_id
	, att.no_of_students
	, staff.preferred_name
	, staff.surname
	, staff.staff_reference
	, CONVERT(TIME,att.activity_time) from_time
	, CONVERT(TIME,att.activity_end) to_time
	, act.a_name activity_name
	, act.a_reference activity_ref
	, ma.ma_activitymodule module_id
	, act.a_reference + ',' + staff.staff_reference + ',' + CONVERT(VARCHAR(10),att.no_of_students)  detls
	FROM pbi.ru_timeslots ts
	LEFT JOIN @activity_times att
		ON (att.activity_time >= ts.start_time 
			AND att.activity_time < ts.end_time)
		OR (att.activity_end > ts.start_time 
			AND att.activity_end < ts.end_time)
		OR (att.activity_time < ts.start_time
			AND att.activity_end > ts.end_time)
	LEFT JOIN capd_staffactivity sa
		ON att.activity_id = sa.sa_activity
		AND att.staff_id = sa.sa_activitystaff
	LEFT JOIN capd_activity act
		ON sa.sa_activity = act.a_id
	LEFT JOIN capd_moduleactivity ma
		ON act.a_id = ma.ma_activity
	LEFT JOIN mis.v_staff_details staff
		ON sa.sa_activitystaff = staff.staff_id
	WHERE ts.start_of_week >= @start_of_week
	;
END

