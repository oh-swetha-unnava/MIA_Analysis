-------- MIA Analysis Variables ----------

--------------- MIA Devices --------------
--- Creating a table with all MIA devices

CREATE TABLE SUNNAVA.MIA_DEVICES AS
SELECT
	A.CASE_ID,
	A.ASSET_NAME,
	A.DEVICE_TYPE,
	A.REASON_CODE,
	B.ID AS CASE_ASSET_ID,
	B.RESOLUTION,
	B.CREATED_DATE,
	B.CLOSED_DATE,
	D.CLIENT_ID,
	C.STATUS AS AMS_STATUS,
  C.AMS_ID,
	E.CMH_ID
FROM CUSTOMER_OPS.CASE_REASON_CODES A
INNER JOIN SALESFORCE.CASE_ASSETS B ON A.CASE_ID = B.CASE AND A.ASSET_NAME = B.ASSET_NAME
LEFT JOIN SALESFORCE.CASES E ON B.CASE = E.CASE_ID
LEFT JOIN AMS.ASSETS_HISTORY C ON UPPER(B.ASSET_NAME) = UPPER(C.ASSET_TAG) AND E.CREATED_DATE::DATE = (C.EXPORT_DATE -1)::DATE
LEFT JOIN MDM.DEVICES D ON UPPER(C.SOURCE_SYSTEM) = 'MDM' AND D.ID = C.SOURCE_SYSTEM_ID
WHERE UPPER(A.CASE_ASSET_TYPE) = 'MIA'
AND NVL(B.CLOSED_DATE, '2020-11-30') >= B.CREATED_DATE
AND B.CREATED_DATE >= '2020-06-01';

SELECT COUNT(DISTINCT ASSET_NAME) FROM SUNNAVA.MIA_DEVICES ; --36156

select DEVICE_TYPE_2, count(asset_name) from (
select distinct asset_name,CASE WHEN DEVICE_TYPE IN ('TV Screen','Waiting Room Screen') THEN 'WRTV'
                           WHEN DEVICE_TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                           WHEN DEVICE_TYPE LIKE ('%Infusion Room Tablet%') THEN 'IRT'
                           ELSE UPPER(DEVICE_TYPE) END AS DEVICE_TYPE_2
from SUNNAVA.MIA_DEVICES )
group by 1;
--TABLET	14471
--IRT	1241
--WRTV	9223
--WALLBOARD	10308
--WAITING ROOM WIFI	914

--------------- Non MIA Devices ----------
--- Creating a table with all Non - MIA devices

drop table SUNNAVA.NON_MIA_DEVICES_v2;
CREATE TABLE SUNNAVA.NON_MIA_DEVICES_v2 AS
SELECT distinct C.AMS_ID, C.ASSET_TAG, D.CLIENT_ID,C.CMH_ID,
CASE WHEN TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer') THEN 'WRTV'
     WHEN TYPE IN ('InfusionRoomTablet') THEN 'IRT'
     WHEN TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
     ELSE UPPER(TYPE) END AS DEVICE_TYPE
FROM AMS.ASSETS_HISTORY C
LEFT JOIN MDM.DEVICES D ON UPPER(C.SOURCE_SYSTEM) = 'MDM' AND D.ID = C.SOURCE_SYSTEM_ID
WHERE C.ASSET_TAG NOT IN ( SELECT DISTINCT ASSET_NAME
                           FROM CUSTOMER_OPS.CASE_REASON_CODES A
                           WHERE UPPER(A.CASE_ASSET_TYPE) = 'MIA' )
and upper(c.status) = upper('Installed')
and (c.export_date >= cast('2020-06-01' as date) and c.export_date <= cast('2020-11-30' as date)) ;


SELECT COUNT(DISTINCT ASSET_TAG),count(*) FROM SUNNAVA.NON_MIA_DEVICES_v2 ;
--116823	117527

select device_type,count(distinct asset_tag) from sunnava.NON_MIA_DEVICES_v2
group by 1;
/*
WRTV			4252
IRT				1039
WALLBOARD	34141
					54738
TABLET		22679
*/

drop table sunnava.non_mia_devices_ctdwn;
create table sunnava.non_mia_devices_ctdwn as
select * from( select distinct a.*,row_number() over (partition by DEVICE_TYPE order by a.asset_tag) as rn
							 from (select distinct  a.*
								 		 from SUNNAVA.NON_MIA_DEVICES_v2 a
										 where device_type is not null )a)
where rn <= 25000;

select device_type,count(distinct asset_tag) from sunnava.non_mia_devices_ctdwn
group by 1;

/*
WRTV			4252
IRT				1039
WALLBOARD	19958
TABLET		19958
*/

SELECT COUNT(DISTINCT ASSET_TAG) FROM SUNNAVA.non_mia_devices_ctdwn ; --45207

---------------Internal-------------------

---------------- 1.Software --------------
------ Software Version
------ Free Space % ( least FREE_DISK_SPACE of the device_type/ FREE_DISK_SPACE of the device)

---------------- 2.HARDWARE --------------
------ Is_battery_charing BOOLEAN FLAG


SELECT DISTINCT TYPE FROM MDM.DEVICES_HISTORY;
/*
AndroidMediaPlayer
Wallboard
UnregisteredTablet
InfusionRoomTablet
Tablet
LinuxMediaPlayer
*/

SELECT DISTINCT DEVICE_TYPE FROM SUNNAVA.MIA_DEVICES ;
/*
Waiting Room Wifi
Wallboard
TABLET
Infusion Room Tablet
Tablet
TV Screen
Waiting Room Screen
*/


SELECT DISTINCT ASSET_NAME FROM SUNNAVA.MIA_DEVICES WHERE DEVICE_TYPE IN ('TV Screen','Waiting Room Screen')-- 9223
INTERSECT
SELECT DISTINCT  asset_id FROM MDM.DEVICES_HISTORY WHERE TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer');
--7965

SELECT DISTINCT ASSET_NAME FROM SUNNAVA.MIA_DEVICES WHERE DEVICE_TYPE IN ('Wallboard')--10308
INTERSECT
SELECT DISTINCT  asset_id FROM MDM.DEVICES_HISTORY WHERE TYPE IN ('Wallboard');
--10308

SELECT DISTINCT ASSET_NAME FROM SUNNAVA.MIA_DEVICES WHERE DEVICE_TYPE IN ('UnregisteredTablet','Tablet')--14470
INTERSECT
SELECT DISTINCT  asset_id FROM MDM.DEVICES_HISTORY WHERE UPPER(TYPE) IN ('TABLET');
--14351

SELECT DISTINCT ASSET_NAME FROM SUNNAVA.MIA_DEVICES WHERE DEVICE_TYPE LIKE ('%Infusion Room Tablet%')--1241
INTERSECT
SELECT DISTINCT  asset_id FROM MDM.DEVICES_HISTORY WHERE TYPE IN ('InfusionRoomTablet');
--1241
--------------------- MIA DEVICES ----------------------------
WITH DEVICE_SOFTWARE AS (
SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2 AS DEVICE_TYPE,software_version,free_disk_space,is_battery_charging,battery_charge_level
FROM (SELECT DISTINCT A.ASSET_NAME, a.DEVICE_TYPE_2 , EXPORT_DATE,B.DEVICE_APK_VERSION AS software_version,B.free_disk_space,
      B.is_battery_charging,B.battery_charge_level,
      case when B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE then start_date end as startdate,
      row_number() over (partition by a.asset_name,startdate order by export_date desc) as rn
      FROM (SELECT A.ASSET_NAME,DEVICE_TYPE_2,
                  NVL(LAG(CLOSED_DATE) OVER (PARTITION BY ASSET_NAME ORDER BY CREATED_DATE),CREATED_DATE-7) AS START_DATE,
                  NVL(CREATED_DATE,CAST('2020-11-30' AS DATE)) AS END_DATE
            FROM( SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2,created_date,closed_date
                  FROM  (SELECT DISTINCT ASSET_NAME, DEVICE_TYPE,created_date,closed_date,
                          CASE WHEN DEVICE_TYPE IN ('TV Screen','Waiting Room Screen') THEN 'WRTV'
                           WHEN DEVICE_TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                           WHEN DEVICE_TYPE LIKE ('%Infusion Room Tablet%') THEN 'IRT'
                           ELSE UPPER(DEVICE_TYPE) END AS DEVICE_TYPE_2
                         FROM SUNNAVA.MIA_DEVICES)A) A) A
LEFT JOIN MDM.DEVICES_HISTORY B ON A.ASSET_NAME = B.ASSET_ID
                                AND (B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE) -- Anchoring on the recent capture ( one week) of data prior to MIA case creation
--where A.asset_name = 'T01E111435'
order by 5,2 desc)
WHERE RN =1),

MIN_FREE_SPACE_BY_TYPE AS
(SELECT DEVICE_TYPE_2 AS DEVICE_TYPE, MIN(free_disk_space) AS MIN_FREE_SPACE
           FROM ( SELECT TYPE,free_disk_space,
                  CASE WHEN TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer') THEN 'WRTV'
                   WHEN TYPE IN ('InfusionRoomTablet') THEN 'IRT'
                   WHEN TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                   ELSE UPPER(TYPE) END AS DEVICE_TYPE_2
                  FROM MDM.DEVICES_HISTORY
                  WHERE free_disk_space >0)
           GROUP BY  DEVICE_TYPE_2)

SELECT A.*, CASE WHEN A.DEVICE_TYPE =  B.DEVICE_TYPE THEN MIN_FREE_SPACE END AS MIN_FREE_SPACE_BY_TYPE
FROM   DEVICE_SOFTWARE A LEFT JOIN  MIN_FREE_SPACE_BY_TYPE B ON A. DEVICE_TYPE = B.DEVICE_TYPE  ;

---------------- 2.HARDWARE --------------
-- SKU Number
-- Model Number
-- Model Manufacturer

WITH DEVICE_HARDWARE AS (
SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2 AS DEVICE_TYPE,MANUFACTURER ,MODEL,
       SKU , processor, SCREEN_SIZE
FROM (SELECT DISTINCT A.ASSET_NAME, a.DEVICE_TYPE_2 , EXPORT_DATE,B.MANUFACTURER ,B.MODEL,
      B.SKU_CODE AS SKU , B.processor, B.SCREEN_SIZE,
      case when B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE then start_date end as startdate,
      row_number() over (partition by a.asset_name,startdate order by export_date desc) as rn
      FROM (SELECT A.ASSET_NAME,DEVICE_TYPE_2,
                  NVL(LAG(CLOSED_DATE) OVER (PARTITION BY ASSET_NAME ORDER BY CREATED_DATE),CREATED_DATE-7) AS START_DATE,
                  NVL(CREATED_DATE,CAST('2020-11-30' AS DATE)) AS END_DATE
            FROM( SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2,created_date,closed_date
                  FROM  (SELECT DISTINCT ASSET_NAME, DEVICE_TYPE,created_date,closed_date,
                          CASE WHEN DEVICE_TYPE IN ('TV Screen','Waiting Room Screen') THEN 'WRTV'
                           WHEN DEVICE_TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                           WHEN DEVICE_TYPE LIKE ('%Infusion Room Tablet%') THEN 'IRT'
                           ELSE UPPER(DEVICE_TYPE) END AS DEVICE_TYPE_2
                         FROM SUNNAVA.MIA_DEVICES)A) A) A
LEFT JOIN (SELECT B.ASSET_TAG, MANUFACTURER,MODEL,PROCESSOR,SKU_CODE,SCREEN_SIZE,A.EXPORT_DATE
          FROM  ASSET_STATUS_ENGINE.SKU_HISTORY A INNER JOIN AMS.ASSETS B ON A.SKU_CODE = B.SKU) B ON A.ASSET_NAME = B.ASSET_TAG
                                AND (B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE) -- Anchoring on the recent capture ( one week) of data prior to MIA case creation
where A.asset_name = 'T01E111435'
order by 5,2 desc)
WHERE RN =1)

SELECT A.*
FROM   DEVICE_HARDWARE A  ;


--------------- 4.POWEROFF EVENT --------------
-- Avg # of times a device has extended power off event
-- Avg of # days device is powered off

select ASSET_ID, count(distinct event_start) as avg_times, avg( case when  final>0 then final end) as avg_days
from (select a.*, case when days_from_minutes is null then days_from_msg
                       when days_from_minutes >= days_from_msg then days_from_minutes
                       when days_from_minutes = 0 then 0
				               end as final
      from (select distinct asset_id,event_end,event_start,message,regexp_substr(message, '[0-9]+'),
                   estimated_power_off_minutes,
                   CAST(estimated_power_off_minutes/86400 AS INTEGER) as days_from_minutes,
                   CAST(regexp_substr(message, '[0-9]+')AS INTEGER) as days_from_msg
                   , estimated_power_off_minutes/86400
            FROM EVENT.POWEROFF_EVENTS) a)
where (event_start >= CAST('2020-06-01' AS DATE) AND event_start <= CAST('2020-11-30' AS DATE) )
group by ASSET_ID  ;

-------- EXTERNAL -----------
--------- CLINIC -----------

---State
-- Facility_type
-- Specialty
-- Ranking
-- Flag if clinic has MIA cases during Jun’ 20 - Nov’ 20

--------------------- MIA DEVICES -------------

SELECT DISTINCT A.ASSET_NAME,A.CMH_ID,B.billing_state_province AS STATE, B.Facility_type,B.RANKING,B.account_type,
B.lead_category AS SPECIALTY,business_tier, CASE WHEN A.CMH_ID = C.CMH_ID THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
FROM SUNNAVA.MIA_DEVICES A
LEFT JOIN salesforce.accounts b on a.cmh_id = b.cmh_id
LEFT JOIN (SELECT  CMH_ID, CASE WHEN COUNT(DISTINCT  case_asset_id) > 0 THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
            FROM ( SELECT DISTINCT A.asset_name,E.CMH_ID,b.id AS case_asset_id,b.created_date
		            		FROM customer_ops.case_reason_codes  A
		            		INNER JOIN salesforce.case_assets b ON a.case_id = b."case" AND a.asset_name = b.asset_name
		            		LEFT JOIN salesforce.cases e ON b."case" = e.case_id
		            		WHERE a.case_asset_type = 'MIA'
		            		AND (B.created_date >= '2020-06-01'
		            		AND B.created_date <= '2020-11-30'))
            GROUP BY CMH_ID) C ON A.CMH_ID = C.CMH_ID;


---------------------- NON MIA DEVICES -------------
SELECT DISTINCT A.ASSET_NAME,A.CMH_ID,B.billing_state_province AS STATE, B.Facility_type,B.RANKING,B.account_type,
B.lead_category AS SPECIALTY,business_tier, CASE WHEN A.CMH_ID = C.CMH_ID THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
FROM SUNNAVA.NON_MIA_DEVICES A
LEFT JOIN salesforce.accounts b on a.cmh_id = b.cmh_id
LEFT JOIN (SELECT  CMH_ID, CASE WHEN COUNT(DISTINCT  case_asset_id) > 0 THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
            FROM ( SELECT DISTINCT A.asset_name,E.CMH_ID,b.id AS case_asset_id,b.created_date
		            		FROM customer_ops.case_reason_codes  A
		            		INNER JOIN salesforce.case_assets b ON a.case_id = b."case" AND a.asset_name = b.asset_name
		            		LEFT JOIN salesforce.cases e ON b."case" = e.case_id
		            		WHERE a.case_asset_type = 'MIA'
		            		AND (B.created_date >= '2020-06-01'
		            		AND B.created_date <= '2020-11-30'))
            GROUP BY CMH_ID) C ON A.CMH_ID = C.CMH_ID;

--------------- 3. NETWORK -----------------
-- Avg # of times a device has network issues during Jun’ 20 - Nov’ 20
-- Flagging devices with # of months having the issues

create table sunnava.network_mia as
select asset_tag,extract(month from cast(export_date as date)) as month, count(distinct export_date) as export_days,
 			 count(distinct to_char(last_pinged_at, 'yyyy-mm-dd')) as ntw_days,
			 count(distinct export_date) - count(distinct to_char(last_pinged_at, 'yyyy-mm-dd'))
from ams.assets_history
where asset_tag in (select distinct asset_tag from sunnava.mia_devices )
and ( export_date >= cast('2020-06-01' as date) and export_date <= cast('2020-11-30' as date))
group by 1,2;




create table sunnava.network_nonmia as
select asset_tag,extract(month from cast(export_date as date)) as month, count(distinct export_date) as export_days,
       count(distinct to_char(last_pinged_at, 'yyyy-mm-dd')) as ntw_days,
			 count(distinct export_date) - count(distinct to_char(last_pinged_at, 'yyyy-mm-dd'))
from ams.assets_history
where asset_tag in (select distinct asset_tag from sunnava.non_mia_devices_ctdwn )
and ( export_date >= cast('2020-06-01' as date) and export_date <= cast('2020-11-30' as date))
group by 1,2;


------------------------------------ AGGREAGATED REDSHIFT VARIABLES ----------------------
----- MIA DEVICES ------
DROP TABLE SUNNAVA.MIA_DEVICES_VAR_V1;
CREATE TABLE SUNNAVA.MIA_DEVICES_VAR_V1 AS
WITH DEVICE_SOFTWARE AS (
SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2 AS DEVICE_TYPE,software_version,free_disk_space,is_battery_charging,battery_charge_level
FROM (SELECT DISTINCT A.ASSET_NAME, a.DEVICE_TYPE_2 , EXPORT_DATE,B.DEVICE_APK_VERSION AS software_version,B.free_disk_space,
      B.is_battery_charging,B.battery_charge_level,
      case when B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE then start_date end as startdate,
      row_number() over (partition by a.asset_name,startdate order by export_date desc) as rn
      FROM (SELECT A.ASSET_NAME,DEVICE_TYPE_2,
                  NVL(LAG(CLOSED_DATE) OVER (PARTITION BY ASSET_NAME ORDER BY CREATED_DATE),CREATED_DATE-7) AS START_DATE,
                  NVL(CREATED_DATE,CAST('2020-11-30' AS DATE)) AS END_DATE
            FROM( SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2,created_date,closed_date
                  FROM  (SELECT DISTINCT ASSET_NAME, DEVICE_TYPE,created_date,closed_date,
                          CASE WHEN DEVICE_TYPE IN ('TV Screen','Waiting Room Screen') THEN 'WRTV'
                           WHEN DEVICE_TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                           WHEN DEVICE_TYPE LIKE ('%Infusion Room Tablet%') THEN 'IRT'
                           ELSE UPPER(DEVICE_TYPE) END AS DEVICE_TYPE_2
                         FROM SUNNAVA.MIA_DEVICES)A) A) A
LEFT JOIN MDM.DEVICES_HISTORY B ON A.ASSET_NAME = B.ASSET_ID
                                AND (B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE) -- Anchoring on the recent capture ( one week) of data prior to MIA case creation
--where A.asset_name = 'T01E111435'
order by 5,2 desc)
WHERE RN =1),

MIN_FREE_SPACE_BY_TYPE AS
(SELECT DEVICE_TYPE_2 AS DEVICE_TYPE, MIN(free_disk_space) AS MIN_FREE_SPACE
           FROM ( SELECT TYPE,free_disk_space,
                  CASE WHEN TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer') THEN 'WRTV'
                   WHEN TYPE IN ('InfusionRoomTablet') THEN 'IRT'
                   WHEN TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                   ELSE UPPER(TYPE) END AS DEVICE_TYPE_2
                  FROM MDM.DEVICES_HISTORY
                  WHERE free_disk_space >0)
           GROUP BY  DEVICE_TYPE_2),

DEVICE_HARDWARE AS (
SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2 AS DEVICE_TYPE,MANUFACTURER ,MODEL,
       SKU , processor, SCREEN_SIZE
FROM (SELECT DISTINCT A.ASSET_NAME, a.DEVICE_TYPE_2 , EXPORT_DATE,B.MANUFACTURER ,B.MODEL,
      B.SKU_CODE AS SKU , B.processor, B.SCREEN_SIZE,
      case when B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE then start_date end as startdate,
      row_number() over (partition by a.asset_name,startdate order by export_date desc) as rn
      FROM (SELECT A.ASSET_NAME,DEVICE_TYPE_2,
                  NVL(LAG(CLOSED_DATE) OVER (PARTITION BY ASSET_NAME ORDER BY CREATED_DATE),CREATED_DATE-7) AS START_DATE,
                  NVL(CREATED_DATE,CAST('2020-11-30' AS DATE)) AS END_DATE
            FROM( SELECT DISTINCT ASSET_NAME, DEVICE_TYPE_2,created_date,closed_date
                  FROM  (SELECT DISTINCT ASSET_NAME, DEVICE_TYPE,created_date,closed_date,
                          CASE WHEN DEVICE_TYPE IN ('TV Screen','Waiting Room Screen') THEN 'WRTV'
                           WHEN DEVICE_TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                           WHEN DEVICE_TYPE LIKE ('%Infusion Room Tablet%') THEN 'IRT'
                           ELSE UPPER(DEVICE_TYPE) END AS DEVICE_TYPE_2
                         FROM SUNNAVA.MIA_DEVICES)A) A) A
LEFT JOIN (SELECT B.ASSET_TAG, MANUFACTURER,MODEL,PROCESSOR,SKU_CODE,SCREEN_SIZE,A.EXPORT_DATE
          FROM  ASSET_STATUS_ENGINE.SKU_HISTORY A INNER JOIN AMS.ASSETS B ON A.SKU_CODE = B.SKU) B ON A.ASSET_NAME = B.ASSET_TAG
                                AND (B.EXPORT_DATE <= A.END_DATE AND B.EXPORT_DATE>= A.START_DATE) -- Anchoring on the recent capture ( one week) of data prior to MIA case creation
--where A.asset_name = 'T01E111435'
order by 5,2 desc)
WHERE RN =1)  ,

POWEROFF AS (
select ASSET_ID, count(distinct event_start) as avg_times, avg( case when  final>0 then final end) as avg_days
from (select a.*, case when days_from_minutes is null then days_from_msg
                       when days_from_minutes >= days_from_msg then days_from_minutes
                       when days_from_minutes = 0 then 0
				               end as final
      from (select distinct asset_id,event_end,event_start,message,regexp_substr(message, '[0-9]+'),
                   estimated_power_off_minutes,
                   CAST(estimated_power_off_minutes/86400 AS INTEGER) as days_from_minutes,
                   CAST(regexp_substr(message, '[0-9]+')AS INTEGER) as days_from_msg
                   , estimated_power_off_minutes/86400
            FROM EVENT.POWEROFF_EVENTS) a)
where (event_start >= CAST('2020-06-01' AS DATE) AND event_start <= CAST('2020-11-30' AS DATE) )
group by ASSET_ID  ),


CLINIC AS (
SELECT DISTINCT A.ASSET_NAME,A.CMH_ID,B.billing_state_province AS STATE, B.Facility_type,B.RANKING,B.account_type,
B.lead_category AS SPECIALTY,business_tier, CASE WHEN A.CMH_ID = C.CMH_ID THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
FROM SUNNAVA.MIA_DEVICES A
LEFT JOIN salesforce.accounts b on a.cmh_id = b.cmh_id
LEFT JOIN (SELECT  CMH_ID, CASE WHEN COUNT(DISTINCT  case_asset_id) > 0 THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
            FROM ( SELECT DISTINCT A.asset_name,E.CMH_ID,b.id AS case_asset_id,b.created_date
            		FROM customer_ops.case_reason_codes  A
            		INNER JOIN salesforce.case_assets b ON a.case_id = b."case" AND a.asset_name = b.asset_name
            		LEFT JOIN salesforce.cases e ON b."case" = e.case_id
            		WHERE a.case_asset_type = 'MIA'
            		AND (B.created_date >= '2020-06-01'
            		AND B.created_date <= '2020-11-30'))
            GROUP BY CMH_ID) C ON A.CMH_ID = C.CMH_ID)

SELECT distinct A.*, CASE WHEN A.DEVICE_TYPE =  B.DEVICE_TYPE THEN MIN_FREE_SPACE END AS MIN_FREE_SPACE_BY_TYPE,
MANUFACTURER ,MODEL, SKU , processor, SCREEN_SIZE,
avg_times,avg_days,
STATE,Facility_type,RANKING,account_type,SPECIALTY,business_tier,CLINIC_HAD_MIA
FROM   DEVICE_SOFTWARE A LEFT JOIN  MIN_FREE_SPACE_BY_TYPE B ON A. DEVICE_TYPE = B.DEVICE_TYPE
LEFT JOIN DEVICE_HARDWARE C ON A.asset_name = C.asset_name
LEFT JOIN POWEROFF D ON A.ASSET_NAME = D.ASSET_ID
LEFT JOIN CLINIC E ON A.asset_name = E.asset_name;

SELECT COUNT(*), COUNT(DISTINCT ASSET_NAME) FROM SUNNAVA.MIA_DEVICES_VAR_V1 ;
--43585	36156

SELECT device_type, COUNT(DISTINCT ASSET_NAME) FROM SUNNAVA.MIA_DEVICES_VAR_V1
GROUP BY device_type;
/*
IRT								1241
WALLBOARD					10308
WAITING ROOM WIFI	914
WRTV							9223
TABLET						14471
*/

------------------------------------------NON MIA DEVICES--------------------------
DROP TABLE SUNNAVA.NONMIA_DEVICES_VAR_V1;
CREATE TABLE SUNNAVA.NONMIA_DEVICES_VAR_V1 AS
WITH DEVICE_SOFTWARE AS (
SELECT DISTINCT A.*,device_apk_version AS software_version,free_disk_space
FROM(SELECT DISTINCT A.*
		  FROM(SELECT DISTINCT ASSET_TAG, DEVICE_TYPE,is_battery_charging,battery_charge_level,
										row_number() OVER (PARTITION BY ASSET_TAG ORDER BY EXPORT_DATE DESC) AS RN
					 FROM  SUNNAVA.non_mia_devices_ctdwn A
					 LEFT JOIN MDM.DEVICES_HISTORY B ON A.ASSET_TAG = B.ASSET_ID
				                                AND (B.EXPORT_DATE >= CAST('2020-06-01' AS DATE) AND B.EXPORT_DATE <= CAST('2020-11-30' AS DATE))) A
			WHERE RN =1) A
LEFT JOIN (SELECT DISTINCT ASSET_ID, device_apk_version
					 from mdm.DEVICES_HISTORY
					 where  (device_apk_version is not null and device_apk_version not like '%nil%' )
					 AND  (EXPORT_DATE >= CAST('2020-06-01' AS DATE) AND EXPORT_DATE <= CAST('2020-11-30' AS DATE))) B ON A.ASSET_TAG = B.ASSET_ID
LEFT JOIN (SELECT DISTINCT ASSET_ID, free_disk_space
					 from mdm.DEVICES_HISTORY
					 where  free_disk_space > 0
					 AND  (EXPORT_DATE >= CAST('2020-06-01' AS DATE) AND EXPORT_DATE <= CAST('2020-11-30' AS DATE))) C ON A.ASSET_TAG = C.ASSET_ID),

MIN_FREE_SPACE_BY_TYPE AS
(SELECT DEVICE_TYPE_2 AS DEVICE_TYPE, MIN(free_disk_space) AS MIN_FREE_SPACE
           FROM ( SELECT TYPE,free_disk_space,
                  CASE WHEN TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer') THEN 'WRTV'
                   WHEN TYPE IN ('InfusionRoomTablet') THEN 'IRT'
                   WHEN TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
                   ELSE UPPER(TYPE) END AS DEVICE_TYPE_2
                  FROM MDM.DEVICES_HISTORY
                  WHERE free_disk_space >0)
           GROUP BY  DEVICE_TYPE_2),

DEVICE_HARDWARE AS (
SELECT DISTINCT A.ASSET_TAG,A.DEVICE_TYPE,MANUFACTURER ,MODEL, SKU , processor, SCREEN_SIZE
FROM sunnava.non_mia_devices_ctdwn A
LEFT JOIN (SELECT DISTINCT B.ASSET_TAG, MANUFACTURER,MODEL,PROCESSOR,SKU_CODE AS SKU,SCREEN_SIZE,A.EXPORT_DATE
          FROM  ASSET_STATUS_ENGINE.SKU_HISTORY A INNER JOIN AMS.ASSETS B ON A.SKU_CODE = B.SKU) B ON A.ASSET_TAG = B.ASSET_TAG
                                AND (B.EXPORT_DATE >= CAST('2020-06-01' AS DATE) AND B.EXPORT_DATE <= CAST('2020-11-30' AS DATE))

--where A.asset_name = 'T01E111435'
)  ,

POWEROFF AS (
select ASSET_ID, count(distinct event_start) as avg_times, avg( case when  final>0 then final end) as avg_days
from (select a.*, case when days_from_minutes is null then days_from_msg
                       when days_from_minutes >= days_from_msg then days_from_minutes
                       when days_from_minutes = 0 then 0
				               end as final
      from (select distinct asset_id,event_end,event_start,message,regexp_substr(message, '[0-9]+'),
                   estimated_power_off_minutes,
                   CAST(estimated_power_off_minutes/86400 AS INTEGER) as days_from_minutes,
                   CAST(regexp_substr(message, '[0-9]+')AS INTEGER) as days_from_msg
                   , estimated_power_off_minutes/86400
            FROM EVENT.POWEROFF_EVENTS) a)
where (event_start >= CAST('2020-06-01' AS DATE) AND event_start <= CAST('2020-11-30' AS DATE) )
group by ASSET_ID  ),


CLINIC AS (
SELECT DISTINCT A.ASSET_TAG,A.CMH_ID,B.billing_state_province AS STATE, B.Facility_type,B.RANKING,B.account_type,
B.lead_category AS SPECIALTY,business_tier, CASE WHEN A.CMH_ID = C.CMH_ID THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
FROM SUNNAVA.non_mia_devices_ctdwn A
LEFT JOIN salesforce.accounts b on a.cmh_id = b.cmh_id
LEFT JOIN (SELECT  CMH_ID, CASE WHEN COUNT(DISTINCT  case_asset_id) > 0 THEN 1 ELSE 0 END AS CLINIC_HAD_MIA
            FROM ( SELECT DISTINCT A.asset_name,E.CMH_ID,b.id AS case_asset_id,b.created_date
            		FROM customer_ops.case_reason_codes  A
            		INNER JOIN salesforce.case_assets b ON a.case_id = b."case" AND a.asset_name = b.asset_name
            		LEFT JOIN salesforce.cases e ON b."case" = e.case_id
            		WHERE a.case_asset_type = 'MIA'
            		AND (B.created_date >= '2020-06-01'
            		AND B.created_date <= '2020-11-30'))
            GROUP BY CMH_ID) C ON A.CMH_ID = C.CMH_ID)

SELECT distinct A.*, CASE WHEN A.DEVICE_TYPE =  B.DEVICE_TYPE THEN MIN_FREE_SPACE END AS MIN_FREE_SPACE_BY_TYPE,
MANUFACTURER ,MODEL, SKU , processor, SCREEN_SIZE,
avg_times,avg_days,
STATE,Facility_type,RANKING,account_type,SPECIALTY,business_tier,CLINIC_HAD_MIA
FROM   DEVICE_SOFTWARE A LEFT JOIN  MIN_FREE_SPACE_BY_TYPE B ON A. DEVICE_TYPE = B.DEVICE_TYPE
LEFT JOIN DEVICE_HARDWARE C ON A.ASSET_TAG = C.ASSET_TAG
LEFT JOIN POWEROFF D ON A.ASSET_TAG = D.ASSET_ID
LEFT JOIN CLINIC E ON A.ASSET_TAG = E.ASSET_TAG;

SELECT COUNT(*), COUNT(DISTINCT ASSET_TAG) FROM SUNNAVA.NONMIA_DEVICES_VAR_V1 ;
--2077251	45207

SELECT device_type, COUNT(DISTINCT ASSET_TAG) FROM SUNNAVA.NONMIA_DEVICES_VAR_V1
GROUP BY device_type;
/*
WRTV			4252
TABLET		19958
IRT				1039
WALLBOARD	19958
*/

GRANT SELECT ON SUNNAVA.NON_MIA_DEVICES_v2 TO GROUP REPORTING_ROLE;

	--------------------------------   TREASURE DATA VARIABLES ----------------------
	----- Below tables from redshift are exported/mirrored to TD temporary schema
	-- sunnava.MIA_DEVICES  --> temporary.sunnava_mia_devices
	-- sunnava.non_mia_devices_ctdwn --> temporary.sunnava_non_mia_devices_ctdwn

	SELECT device_type, COUNT(DISTINCT ASSET_TAG) FROM TEMPORARY.sunnava_non_mia_devices_ctdwn
	GROUP BY device_type;
	/*
	WRTV          4252
	WALLBOARD     19958
	TABLET        19958
	IRT           1039
	*/

	SELECT device_type, COUNT(DISTINCT ASSET_NAME) FROM TEMPORARY.sunnava_mia_devices
GROUP BY device_type;
/*
TABLET                  1
Waiting Room Wifi       914
Infusion Room Tablet    1241
Tablet                  14470
Wallboard               10308
Waiting Room Screen     7992
TV Screen               1233
*/

	--------------- 3. NETWORK -----------------
	-- Avg # of times a device has network issues during Jun’ 20 - Nov’ 20
	-- Flagging devices with # of months having the issues

	select count(distinct asset_id)
	from event.events
	where (td_time_range(event_start_time/1000, '2020-06-01', '2020-11-30', 'US/Central'))
	and asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
	                   where upper(device_type) like upper('%wallboard%'))
	and event_name like '%ExtendedNetworkOffEvent%' ;
	--156

	select min( extract ( month from cast(td_time_format(event_start_time/1000, 'yyyy-MM-dd')as date) ) ) ,
max( extract ( month from cast(td_time_format(event_start_time/1000, 'yyyy-MM-dd')as date) ) )
from event.events
where (td_time_range(event_start_time/1000, '2020-06-01', '2020-11-30', 'US/Central'))
and asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
                   where upper(device_type) like upper('%wallboard%'))
and event_name like '%ExtendedNetworkOffEvent%' ;
--11 11

	select asset_id, count(distinct month) as months_withissues, avg(network_issues) as avg_network_issues
	from ( select asset_id, extract ( month from cast(td_time_format(event_start_time/1000, 'yyyy-MM-dd')as date) ) as MONTH,
			 					count(distinct event_id) as network_issues
				 from event.events
				 where (td_time_range(event_start_time/1000, '2020-06-01', '2020-11-30', 'US/Central'))
				 and asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
	                   			where upper(device_type) like upper('%wallboard%'))
				 and event_name like '%ExtendedNetworkOffEvent%'
				 group by 1,2)
	group by 1;

	---------------- 5.ACTIVITY ----------------
	-- daily Avg # of video ads per month
	-- daily AVG # OF banner ads per month
	-- daily Avg # of campaigns per month
	-- daily Avg duration of the ads per month
	-- daily Avg # of users per day per month
	-- Brands of the campaigns run for


	--------------------------------- WALLBOARD ---------------------------------------

	select distinct ad_type from wallboard.daily_content_displays_sas;
-- In Stream -- video ad
-- Banner
-- Interactive

select distinct ad_type
from wallboard.daily_content_displays_sas a
inner join (select distinct id, asset_id from mdm.devices) b
on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
and b.asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
                   where upper(device_type) like upper('%wallboard%'));
-- Interactive
-- In Stream


-- Avg # of video ads
-- AVG # OF banner ads
-- Avg # of campaigns
-- Avg duration of the ads

------------------------ MIA DEVICES ---------------
WITH MONTHLY_AVG AS (
	select asset_id, avg( campaigns) as avg_campaigns
	from( select b.asset_id,extract(month from cast(day as date)),
							 count(distinct campaign_id) as campaigns
				from wallboard.daily_content_displays_sas a
				inner join (select distinct id, asset_id from mdm.devices) b
				on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
				where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
				and b.asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
									 					where upper(device_type) like upper('%wallboard%'))
				group by 1,2)
	group by 1 ),
DAILY_AVG AS
	(select asset_id, extract(month from CAST(campaign_DATE AS DATE) ) AS MONTH,
					avg(video_dispalys) as avg_video_dispalys, avg(Banner_dispalys) as avg_Banner_dispalys,
					avg(video_duration) as avg_video_duration,avg(Banner_duration) as avg_Banner_duration
	from( select b.asset_id,td_time_format(time, 'yyyy-MM-dd') AS campaign_DATE,
							sum(case when upper(ad_type) like upper('%In%Stream%') then total_displays end ) as video_dispalys,
							sum(case when upper(ad_type) like upper('%Banner%') then total_displays end ) as Banner_dispalys,
							sum(case when upper(ad_type) like upper('%In%Stream%') then total_duration end ) as video_duration,
							sum(case when upper(ad_type) like upper('%Banner%') then total_duration end ) as Banner_duration
				from wallboard.daily_content_displays_sas a
				inner join (select distinct id, asset_id from mdm.devices) b
					on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
				where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
				and b.asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
                   				 where upper(device_type) like upper('%wallboard%'))
				group by 1,2)
group by 1,2)
SELECT DISTINCT A.*,
			 CASE WHEN MONTH = 6 THEN avg_video_dispalys ELSE 0 END AS JUNE_avg_video_dispalys,
			 CASE WHEN MONTH = 7 THEN avg_video_dispalys ELSE 0 END AS JUL_avg_video_dispalys,
			 CASE WHEN MONTH = 8 THEN avg_video_dispalys ELSE 0 END AS AUG_avg_video_dispalys,
			 CASE WHEN MONTH = 9 THEN avg_video_dispalys ELSE 0 END AS SEPT_avg_video_dispalys,
			 CASE WHEN MONTH = 10 THEN avg_video_dispalys ELSE 0 END AS OCT_avg_video_dispalys,
			 CASE WHEN MONTH = 11 THEN avg_video_dispalys ELSE 0 END AS NOV_avg_video_dispaly,
			 CASE WHEN MONTH = 6 THEN avg_video_duration ELSE 0 END AS JUNE_avg_video_duration,
			 CASE WHEN MONTH = 7 THEN avg_video_duration ELSE 0 END AS JUL_avg_video_duration,
			 CASE WHEN MONTH = 8 THEN avg_video_duration ELSE 0 END AS AUG_avg_video_duration,
			 CASE WHEN MONTH = 9 THEN avg_video_duration ELSE 0 END AS SEPT_avg_video_duration,
			 CASE WHEN MONTH = 10 THEN avg_video_duration ELSE 0 END AS OCT_avg_video_duration,
			 CASE WHEN MONTH = 11 THEN avg_video_duration ELSE 0 END AS NOV_avg_video_duration
FROM 	MONTHLY_AVG A LEFT JOIN DAILY_AVG	 B ON A.ASSET_ID = B.ASSET_ID;

------------------------ NONMIA DEVICES ---------------
WITH MONTHLY_AVG AS (
	select asset_id, avg( campaigns) as avg_campaigns
	from( select b.asset_id,extract(month from cast(day as date)),
							 count(distinct campaign_id) as campaigns
				from wallboard.daily_content_displays_sas a
				inner join (select distinct id, asset_id from mdm.devices) b
				on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
				where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
				and b.asset_id in (select distinct asset_tag from temporary.sunnava_non_mia_devices_ctdwn
									 					where upper(device_type) like upper('%wallboard%'))
				group by 1,2)
	group by 1 ),
DAILY_AVG AS
	(select asset_id, extract(month from CAST(campaign_DATE AS DATE) ) AS MONTH,
					avg(video_dispalys) as avg_video_dispalys, avg(Banner_dispalys) as avg_Banner_dispalys,
					avg(video_duration) as avg_video_duration,avg(Banner_duration) as avg_Banner_duration
	from( select b.asset_id,td_time_format(time, 'yyyy-MM-dd') AS campaign_DATE,
							sum(case when upper(ad_type) like upper('%In%Stream%') then total_displays end ) as video_dispalys,
							sum(case when upper(ad_type) like upper('%Banner%') then total_displays end ) as Banner_dispalys,
							sum(case when upper(ad_type) like upper('%In%Stream%') then total_duration end ) as video_duration,
							sum(case when upper(ad_type) like upper('%Banner%') then total_duration end ) as Banner_duration
				from wallboard.daily_content_displays_sas a
				inner join (select distinct id, asset_id from mdm.devices) b
					on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
				where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
				and b.asset_id in (select distinct asset_tag from temporary.sunnava_non_mia_devices_ctdwn
                   				 where upper(device_type) like upper('%wallboard%'))
				group by 1,2)
group by 1,2)
SELECT DISTINCT A.*,
			 CASE WHEN MONTH = 6 THEN avg_video_dispalys ELSE 0 END AS JUNE_avg_video_dispalys,
			 CASE WHEN MONTH = 7 THEN avg_video_dispalys ELSE 0 END AS JUL_avg_video_dispalys,
			 CASE WHEN MONTH = 8 THEN avg_video_dispalys ELSE 0 END AS AUG_avg_video_dispalys,
			 CASE WHEN MONTH = 9 THEN avg_video_dispalys ELSE 0 END AS SEPT_avg_video_dispalys,
			 CASE WHEN MONTH = 10 THEN avg_video_dispalys ELSE 0 END AS OCT_avg_video_dispalys,
			 CASE WHEN MONTH = 11 THEN avg_video_dispalys ELSE 0 END AS NOV_avg_video_dispaly,
			 CASE WHEN MONTH = 6 THEN avg_video_duration ELSE 0 END AS JUNE_avg_video_duration,
			 CASE WHEN MONTH = 7 THEN avg_video_duration ELSE 0 END AS JUL_avg_video_duration,
			 CASE WHEN MONTH = 8 THEN avg_video_duration ELSE 0 END AS AUG_avg_video_duration,
			 CASE WHEN MONTH = 9 THEN avg_video_duration ELSE 0 END AS SEPT_avg_video_duration,
			 CASE WHEN MONTH = 10 THEN avg_video_duration ELSE 0 END AS OCT_avg_video_duration,
			 CASE WHEN MONTH = 11 THEN avg_video_duration ELSE 0 END AS NOV_avg_video_duration
FROM 	MONTHLY_AVG A LEFT JOIN DAILY_AVG	 B ON A.ASSET_ID = B.ASSET_ID;

-- Brands of the campaigns run for
------MIA_DEVICES ------
select distinct asset_id,c.name
from wallboard.daily_content_displays_sas a
inner join (select distinct id, asset_id from mdm.devices) b
on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
left join mdm.sponsors c
on cast(c.salesforce_campaign_id as varchar) = cast(a.campaign_id  as varchar)
where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
and b.asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
                   where upper(device_type) like upper('%wallboard%'));

---------- NON MIA Devices --------

select distinct asset_id,c.name
from wallboard.daily_content_displays_sas a
inner join (select distinct id, asset_id from mdm.devices) b
on cast(b.id as VARCHAR) = cast(a.device_id as VARCHAR)
left join mdm.sponsors c
on cast(c.salesforce_campaign_id as varchar) = cast(a.campaign_id  as varchar)
where td_time_range(a.time, '2020-06-01', '2020-11-30', 'US/Central')
and b.asset_id in (select distinct asset_tag from temporary.sunnava_non_mia_devices_ctdwn
									 where upper(device_type) like upper('%wallboard%'));

-- Avg # of users/SESSIONS per day per month

---------------------- MIA DEVICES   --------------
select asset_id,
case when month = 6 and session_end_type = 'Timeout' then avg_sessions end as jun_avg_timeout_sessions,
case when month = 6 and session_end_type = 'Crash' then avg_sessions end as jun_avg_Crash_sessions,
case when month = 6 and session_end_type = 'Exit' then avg_sessions end as jun_avg_exit_sessions,
case when month = 7 and session_end_type = 'Timeout' then avg_sessions end as jul_avg_timeout_sessions,
case when month = 7 and session_end_type = 'Crash' then avg_sessions end as jul_avg_Crash_sessions,
case when month = 7 and session_end_type = 'Exit' then avg_sessions end as jul_avg_exit_sessions,
case when month = 8 and session_end_type = 'Timeout' then avg_sessions end as aug_avg_timeout_sessions,
case when month = 8 and session_end_type = 'Crash' then avg_sessions end as aug_avg_Crash_sessions,
case when month = 8 and session_end_type = 'Exit' then avg_sessions end as aug_avg_exit_sessions,
case when month = 9 and session_end_type = 'Timeout' then avg_sessions end as sept_avg_timeout_sessions,
case when month = 9 and session_end_type = 'Crash' then avg_sessions end as sept_avg_Crash_sessions,
case when month = 9 and session_end_type = 'Exit' then avg_sessions end as sept_avg_exit_sessions,
case when month = 10 and session_end_type = 'Timeout' then avg_sessions end as oct_avg_timeout_sessions,
case when month = 10 and session_end_type = 'Crash' then avg_sessions end as oct_avg_Crash_sessions,
case when month = 10 and session_end_type = 'Exit' then avg_sessions end as oct_avg_exit_sessions,
case when month = 11 and session_end_type = 'Timeout' then avg_sessions end as nov_avg_timeout_sessions,
case when month = 11 and session_end_type = 'Crash' then avg_sessions end as nov_avg_Crash_sessions,
case when month = 11 and session_end_type = 'Exit' then avg_sessions end as nov_avg_exit_sessions
from (select asset_id,extract(month from CAST(campaign_DATE AS DATE) ) AS MONTH,session_end_type,avg(sessions) as avg_sessions
			from (select asset_id, td_time_format(event_start_time/1000, 'yyyy-MM-dd') as campaign_DATE ,session_end_type,
									 count(distinct asset_id||session_id) as sessions
						from event.events
						where (td_time_range(event_start_time/1000, '2020-06-01', '2020-11-30', 'US/Central'))
						and asset_id in (select distinct asset_name from temporary.sunnava_mia_devices
                   						where upper(device_type) like upper('%wallboard%'))
						and event_name  like '%SessionEndEvent%'
						group by 1,2,3)
			group by 1,2,3);


----------------------- NON MIA DEVICES --------
select asset_id,
case when month = 6 and session_end_type = 'Timeout' then avg_sessions end as jun_avg_timeout_sessions,
case when month = 6 and session_end_type = 'Crash' then avg_sessions end as jun_avg_Crash_sessions,
case when month = 6 and session_end_type = 'Exit' then avg_sessions end as jun_avg_exit_sessions,
case when month = 7 and session_end_type = 'Timeout' then avg_sessions end as jul_avg_timeout_sessions,
case when month = 7 and session_end_type = 'Crash' then avg_sessions end as jul_avg_Crash_sessions,
case when month = 7 and session_end_type = 'Exit' then avg_sessions end as jul_avg_exit_sessions,
case when month = 8 and session_end_type = 'Timeout' then avg_sessions end as aug_avg_timeout_sessions,
case when month = 8 and session_end_type = 'Crash' then avg_sessions end as aug_avg_Crash_sessions,
case when month = 8 and session_end_type = 'Exit' then avg_sessions end as aug_avg_exit_sessions,
case when month = 9 and session_end_type = 'Timeout' then avg_sessions end as sept_avg_timeout_sessions,
case when month = 9 and session_end_type = 'Crash' then avg_sessions end as sept_avg_Crash_sessions,
case when month = 9 and session_end_type = 'Exit' then avg_sessions end as sept_avg_exit_sessions,
case when month = 10 and session_end_type = 'Timeout' then avg_sessions end as oct_avg_timeout_sessions,
case when month = 10 and session_end_type = 'Crash' then avg_sessions end as oct_avg_Crash_sessions,
case when month = 10 and session_end_type = 'Exit' then avg_sessions end as oct_avg_exit_sessions,
case when month = 11 and session_end_type = 'Timeout' then avg_sessions end as nov_avg_timeout_sessions,
case when month = 11 and session_end_type = 'Crash' then avg_sessions end as nov_avg_Crash_sessions,
case when month = 11 and session_end_type = 'Exit' then avg_sessions end as nov_avg_exit_sessions
from (select asset_id,extract(month from CAST(campaign_DATE AS DATE) ) AS MONTH,session_end_type,avg(sessions) as avg_sessions
			from (select asset_id, td_time_format(event_start_time/1000, 'yyyy-MM-dd') as campaign_DATE ,session_end_type,
									 count(distinct asset_id||session_id) as sessions
						from event.events
						where (td_time_range(event_start_time/1000, '2020-06-01', '2020-11-30', 'US/Central'))
						and asset_id in (select distinct asset_tag from temporary.sunnava_non_mia_devices_ctdwn
                   						where upper(device_type) like upper('%wallboard%'))
						and event_name  like '%SessionEndEvent%'
						group by 1,2,3)
			group by 1,2,3);

-------------------------- WALLBOARD INTERACTIONS -----------------------------
-------- MIA Devivces ---------
select assetid,anatomy_model, avg(touches) as avg_touches
from (
select assetid,anatomy_model,cast(td_time_format(time, 'yyyy-MM-dd')as date) as date,
count(distinct event_datetime ) as touches
from wallboard.model_interaction
where (cast(event_date as date) between cast('2020-06-01' as Date) and  cast('2020-11-30'as Date))
and assetid in (select distinct asset_name from temporary.sunnava_mia_devices
                  where upper(device_type) like upper('%wallboard%'))
group by 1,2,3)
group by 1,2;

-------- NON  MIA DEVICES --------

select assetid,anatomy_model, avg(touches) as avg_touches
from (
select assetid,anatomy_model,cast(td_time_format(time, 'yyyy-MM-dd')as date) as date,
count(distinct event_datetime ) as touches
from wallboard.model_interaction
where (cast(event_date as date) between cast('2020-06-01' as Date) and  cast('2020-11-30'as Date))
and assetid in (select distinct asset_tag from temporary.sunnava_non_mia_devices_ctdwn
                  where upper(device_type) like upper('%wallboard%'))
group by 1,2,3)
group by 1,2;




------------------------------- Ignore any code below --------------------------------------
DROP TABLE SUNNAVA.NON_MIA_DEVICES;
CREATE TABLE SUNNAVA.NON_MIA_DEVICES AS
SELECT C.AMS_ID, C.ASSET_TAG, D.CLIENT_ID,C.CMH_ID,
CASE WHEN TYPE IN ('AndroidMediaPlayer','LinuxMediaPlayer') THEN 'WRTV'
 WHEN TYPE IN ('InfusionRoomTablet') THEN 'IRT'
 WHEN TYPE IN ('UnregisteredTablet','Tablet') THEN 'TABLET'
 ELSE UPPER(TYPE) END AS DEVICE_TYPE
FROM AMS.ASSETS_HISTORY C
LEFT JOIN MDM.DEVICES D ON UPPER(C.SOURCE_SYSTEM) = 'MDM' AND D.ID = C.SOURCE_SYSTEM_ID
WHERE C.ASSET_TAG NOT IN ( SELECT DISTINCT ASSET_NAME
                           FROM CUSTOMER_OPS.CASE_REASON_CODES A
                           WHERE UPPER(A.CASE_ASSET_TYPE) = 'MIA' );

SELECT COUNT(DISTINCT ASSET_TAG) FROM SUNNAVA.NON_MIA_DEVICES ; --261448
