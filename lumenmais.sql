--> Criando a table USERS, que contem dados de usuário, data de inscrição,
--- qual aparelho assiste, país e se teve trial. 

CREATE TABLE users (
	user_id serial primary key,
	signup_date date,
	acquisition_channel text,
	country text,
	primary_device text,
	had_trial boolean

);

select * from users

-------------------------
--> Criando a tabble USAGE_EVENTS que destaca o uso do streaming 

CREATE TABLE usage_events (
	usage_id serial primary key,
	user_id integer,
	session_date date,
	device text,
	genre text,
	watch_minutes integer,
	completed_content boolean

);

select * from usage_events

---------------------
--> Criando a table SUBSCRIPTION_EVENTS que destaca as subscrições do serviço 

CREATE TABLE subscription_events (
	event_id serial primary key,
	user_id integer,
	event_date date,
	event_type text,
	plan text,
	mrr_impact integer,
	cancel_reason varchar (150)

);
alter table subscription_events alter column mrr_impact type numeric (10,2)

select * from subscription_events 


------------
--> BASE -- estado vigente de cada assinante (data de corte atual; exclui quem cancelou)
--- MRR = MONTLY RECURRENT REVENUE 

WITH ranked_events AS (
	SELECT 
	se.*, 
	ROW_NUMBER() OVER (
		PARTITION BY user_id
		ORDER BY event_date DESC, event_id DESC
		) AS rn
	FROM subscription_events se 
	WHERE event_date <= CURRENT_DATE 
	)
	
SELECT user_id, 
event_date AS last_event_date, 
event_type AS last_event_type, 
plan AS current_plan, 
CASE WHEN event_type = 'cancellation' THEN 0 ELSE mrr_impact END as current_mrr 
FROM ranked_events 
WHERE rn = 1
AND event_type NOT IN ('trial_start', 'trial_churn'); 


----
--> MRR Ativo POR PLANO

WITH ranked_events AS (
	select se.*,
	ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_date DESC, event_id DESC) as rn
	FROM subscription_events se),
	current_state as (
select user_id, plan, mrr_impact, event_type
from ranked_events 
where rn = 1 and event_type NOT IN ('trial_start', 'trial churn'))
select plan, 
count(*) as active_subscribers, 
sum(case when event_type = 'cancellation' then 0 else mrr_impact end) as mrr 
from current_state 
group by plan 
order by mrr desc
	
;

----
--> Conversão de trial para pago 

WITH trials as (
select user_id, event_date as trial_date 
from subscription_events 
where event_type = 'trial_start'),

conversions as (
	select t.user_id, t.trial_date, 
	exists (
	select 1 from subscription_events s 
	where s.user_id = t.user_id
		and s.event_type = 'subscription_start'
		and s.event_date >= t.trial_date 
		) AS converted 
		from trials t )
	select u.acquisition_channel, count(*) as total_trials, 
	sum(case when c.converted then 1 else 0 end) as converted, 
	round (100.0 * sum(case when c.converted then 1 else 0 end) / count(*), 1) as conversion_rate_pct 
	from conversions c 
	join users u on u.user_id = c.user_id 
	group by u.acquisition_channel
	order by conversion_rate_pct DESC;

----
--> Engajamento pré-cancelamento 
---> boolean usa-se "then x else y end" para transformar o dado true ou false em número 1 ou 0 

WITH cancellation as ( 
	select user_id, event_date as cancel_date
	from subscription_events 
	where event_type = 'cancellation'), 
engagement_before_cancel as (
	select c.user_id, 
	avg (ue.watch_minutes) as avg_watch_minutes30d, 
	avg(case when ue.completed_content then 1.0 else 0 end) as completion_rate 
	from cancellation c 
	join usage_events ue 
	on ue.user_id = c.user_id 
	and ue.session_date between c.cancel_date - interval '30 days' and c.cancel_date 
	and ue.watch_minutes >=0 
	group by c.user_id),
non_cancelled as (
	select user_id from users 
	where user_id not in (select user_id from cancellation)
), 
engagement_active as (
	select nc.user_id, 
	avg(ue.watch_minutes) as avg_watch_minutes_30d,
	avg(case when ue.completed_content then 1.0 else 0 end) as completion_rate 
	from non_cancelled nc 
	join usage_events ue on ue.user_id = nc.user_id
	and ue.watch_minutes >= 0 
	group by nc.user_id
	)

select 'cancelled' as segment, avg(ec.avg_watch_minutes30d) as avg_watch, 
avg(completion_rate) as avg_completion 
from engagement_before_cancel ec
union all 
select 'active' as segment, avg(ea.avg_watch_minutes_30d), avg(ea.completion_rate)
from engagement_active ea;

------
-->  CRIANDO AS VIEWS 
-- 1. quantas sessões teve, quantos minutos assistiu em média, qual % das sessões completou até o fim, e quando foi a primeira e a última sessão.
CREATE OR REPLACE VIEW vw_usage_summary AS
SELECT
	user_id,
	COUNT(*) AS total_sessions,
	AVG(watch_minutes) AS avg_watch_minutes,
	AVG(CASE WHEN completed_content THEN 1.0 ELSE 0 END) AS completion_rate,
	MAX(session_date) AS last_session_date,
	MIN(session_date) AS first_session_date
FROM usage_events
WHERE watch_minutes >= 0
GROUP BY user_id;

select * from vw_usage_summary

-- 2. Reconstrói o estado atual de cada assinante a partir do histórico de eventos (descarta quem nunca virou pagante e junta dados cadastrais do usuário)
CREATE OR REPLACE VIEW vw_subscriber_current_state AS
WITH ranked_events AS (
	SELECT 
	se.*, 
	ROW_NUMBER() OVER (
		PARTITION BY user_id
		ORDER BY event_date DESC, event_id DESC
		) AS rn
	FROM subscription_events se 
	WHERE event_date <= CURRENT_DATE 
	),
current_state AS (
	SELECT 
	user_id, 
	event_date AS last_event_date, 
	event_type AS last_event_type, 
	plan AS current_plan, 
	CASE WHEN event_type = 'cancellation' THEN 0 ELSE mrr_impact END AS current_mrr,
	cancel_reason
	FROM ranked_events 
	WHERE rn = 1
	AND event_type NOT IN ('trial_start', 'trial_churn')
)
SELECT
	cs.user_id,
	u.signup_date,
	u.acquisition_channel,
	u.country,
	u.primary_device,
	u.had_trial,
	cs.last_event_date,
	cs.last_event_type,
	cs.current_plan,
	cs.current_mrr,
	cs.cancel_reason,
	CASE WHEN cs.last_event_type = 'cancellation' THEN FALSE ELSE TRUE END AS is_active
FROM current_state cs
JOIN users u ON u.user_id = cs.user_id;


-- 3. Junta as duas views anteriores numa só: pega o estado atual de assinatura de cada usuário e adiciona o resumo de uso (sessões, minutos, completion rate)
CREATE OR REPLACE VIEW vw_dashboard_master AS
SELECT
	scs.user_id,
	scs.signup_date,
	scs.acquisition_channel,
	scs.country,
	scs.primary_device,
	scs.current_plan,
	scs.current_mrr,
	scs.is_active,
	scs.cancel_reason,
	us.total_sessions,
	us.avg_watch_minutes,
	us.completion_rate,
	us.last_session_date
FROM vw_subscriber_current_state scs
LEFT JOIN vw_usage_summary us ON us.user_id = scs.user_id;
