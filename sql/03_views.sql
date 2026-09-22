-- Views que consolidam o histórico de eventos em estado atual, prontas para consumo por dashboard/BI.
-- Depende das tabelas criadas em 01_schema.sql.

-- 1. Quantas sessões teve, quantos minutos assistiu em média, qual % das sessões completou até o fim, e quando foi a primeira e a última sessão.
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
