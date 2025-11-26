-- a comment

DECLARE @ay_startyear INT;
DECLARE @from_date DATETIME;
DECLARE @to_date DATETIME;

SELECT @ay_startyear = ay_startyear
, @from_date = ay_start
, @to_date = ay_end
FROM mis.academic_year_sessions sess
WHERE sess.cy_offset = 0
AND sess.ht_half_term = 'AU1';


WITH teacher_classes AS (
	SELECT tch.class_id
	, tch.staff_id
	, tch.from_date
	, tch.to_date
	FROM mis.v_class_teachers tch
	WHERE tch.class_year = @ay_startyear
	AND tch.from_date < getdate() 
	AND tch.to_date >= getdate()
	)
, current_year_activities AS (
	SELECT act.a_id activity_id
	, act.a_reference activity_ref
	, act.a_name activity_name
	, act.a_start activity_start
	, act.a_end activity_end
	, act.a_weekpattern activity_weekpattern
	FROM capd_activity act
	WHERE (
		act.a_start BETWEEN @from_date AND @to_date
		OR
		act.a_end BETWEEN @from_date AND @to_date
		)
	AND act.a_start < getdate()
	AND act.a_end >= getdate()
	)
-- Only want activities for the current year that are in progress
SELECT tc.class_id
, tc.staff_id
, tc.from_date
, tc.to_date
, act.activity_id
, act.activity_name
, act.activity_start
, act.activity_end
, act.activity_weekpattern
FROM teacher_classes tc
INNER JOIN capd_staffactivity sa
	ON tc.staff_id = sa.sa_activitystaff
LEFT JOIN capd_moduleactivity ma
	ON tc.class_id = ma.ma_activitymodule
	AND sa.sa_activity = ma.ma_activity
INNER JOIN current_year_activities act
	ON sa.sa_activity = act.activity_id;