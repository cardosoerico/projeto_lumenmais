-- Consultas analíticas de negócio do projeto LumenMais.
-- Depende das tabelas criadas em 01_schema.sql.
-- As reconstruções de estado aqui usadas são consolidadas em views por 03_views.sql.

-- ============================================================
-- 1. MRR ativo por plano
-- Reconstrói o estado vigente de cada assinante (último evento que não
-- seja de trial) via window function, para não contar cancelamentos e
-- reativações como receita adicional.
-- ============================================================
WITH ultimo_evento AS (
  SELECT
    se.*,
    ROW_NUMBER() OVER (
      PARTITION BY user_id
      ORDER BY event_date DESC, event_id DESC
    ) AS rn
  FROM subscription_events se
  WHERE event_type NOT IN ('trial_start', 'trial_churn')
)
SELECT
  plan,
  COUNT(*) AS assinantes_ativos,
  SUM(mrr_impact) AS mrr_total
FROM ultimo_evento
WHERE rn = 1
  AND event_type <> 'cancellation'
GROUP BY plan
ORDER BY mrr_total DESC;

-- MRR ativo consolidado (todos os planos)
WITH ultimo_evento AS (
  SELECT
    se.*,
    ROW_NUMBER() OVER (
      PARTITION BY user_id
      ORDER BY event_date DESC, event_id DESC
    ) AS rn
  FROM subscription_events se
  WHERE event_type NOT IN ('trial_start', 'trial_churn')
)
SELECT SUM(mrr_impact) AS mrr_ativo_total
FROM ultimo_evento
WHERE rn = 1
  AND event_type <> 'cancellation';

-- ============================================================
-- 2. Conversão trial → pago (geral e por canal de aquisição)
-- Considera convertido quem teve subscription_start após o trial_start,
-- sem trial_churn no meio.
-- ============================================================
WITH trials AS (
  SELECT user_id, event_date AS trial_date
  FROM subscription_events
  WHERE event_type = 'trial_start'
),
conversoes AS (
  SELECT
    t.user_id,
    MAX(CASE WHEN se.event_type = 'subscription_start' THEN 1 ELSE 0 END) AS converteu
  FROM trials t
  LEFT JOIN subscription_events se
    ON se.user_id = t.user_id
   AND se.event_date >= t.trial_date
   AND se.event_type IN ('subscription_start', 'trial_churn')
  GROUP BY t.user_id
)
-- Geral
SELECT
  COUNT(*) AS total_trials,
  SUM(converteu) AS total_convertidos,
  ROUND(100.0 * SUM(converteu) / COUNT(*), 1) AS taxa_conversao_pct
FROM conversoes;

-- Por canal de aquisição
WITH trials AS (
  SELECT se.user_id, se.event_date AS trial_date, u.acquisition_channel
  FROM subscription_events se
  JOIN users u ON u.user_id = se.user_id
  WHERE se.event_type = 'trial_start'
),
conversoes AS (
  SELECT
    t.user_id,
    t.acquisition_channel,
    MAX(CASE WHEN se.event_type = 'subscription_start' THEN 1 ELSE 0 END) AS converteu
  FROM trials t
  LEFT JOIN subscription_events se
    ON se.user_id = t.user_id
   AND se.event_date >= t.trial_date
   AND se.event_type IN ('subscription_start', 'trial_churn')
  GROUP BY t.user_id, t.acquisition_channel
)
SELECT
  acquisition_channel,
  COUNT(*) AS total_trials,
  SUM(converteu) AS total_convertidos,
  ROUND(100.0 * SUM(converteu) / COUNT(*), 1) AS taxa_conversao_pct
FROM conversoes
GROUP BY acquisition_channel
ORDER BY taxa_conversao_pct DESC;

-- ============================================================
-- 3. Engajamento pré-cancelamento
-- Compara minutos assistidos e taxa de conclusão nos 30 dias anteriores
-- ao evento, entre quem cancelou e quem permanece ativo.
-- ============================================================
WITH cancelamentos AS (
  SELECT user_id, event_date AS cancel_date
  FROM subscription_events
  WHERE event_type = 'cancellation'
),
engajamento_cancelados AS (
  SELECT
    c.user_id,
    AVG(ue.watch_minutes) AS avg_watch_minutes,
    AVG(CASE WHEN ue.completed_content THEN 1.0 ELSE 0 END) AS completion_rate
  FROM cancelamentos c
  JOIN usage_events ue
    ON ue.user_id = c.user_id
   AND ue.session_date BETWEEN c.cancel_date - INTERVAL '30 days' AND c.cancel_date
  GROUP BY c.user_id
),
engajamento_ativos AS (
  SELECT
    ue.user_id,
    AVG(ue.watch_minutes) AS avg_watch_minutes,
    AVG(CASE WHEN ue.completed_content THEN 1.0 ELSE 0 END) AS completion_rate
  FROM usage_events ue
  WHERE ue.user_id NOT IN (SELECT user_id FROM cancelamentos)
    AND ue.session_date >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY ue.user_id
)
SELECT
  'cancelados' AS grupo,
  AVG(avg_watch_minutes) AS avg_watch_minutes,
  AVG(completion_rate) AS avg_completion_rate
FROM engajamento_cancelados
UNION ALL
SELECT
  'ativos' AS grupo,
  AVG(avg_watch_minutes) AS avg_watch_minutes,
  AVG(completion_rate) AS avg_completion_rate
FROM engajamento_ativos;

