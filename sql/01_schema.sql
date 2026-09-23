-- Criação das tabelas relacionais do projeto LumenMais.
-- Modelo: users (1) --< subscription_events (N), users (1) --< usage_events (N).
-- Executar antes de 02_analises.sql e 03_views.sql.

CREATE TABLE users (
  user_id             INTEGER PRIMARY KEY,
  signup_date         DATE NOT NULL,
  acquisition_channel VARCHAR(50) NOT NULL,
  country             VARCHAR(2) NOT NULL,
  primary_device      VARCHAR(20) NOT NULL,
  had_trial           BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE subscription_events (
  event_id      INTEGER PRIMARY KEY,
  user_id       INTEGER NOT NULL REFERENCES users(user_id),
  event_date    DATE NOT NULL,
  event_type    VARCHAR(30) NOT NULL,
  -- trial_start, trial_churn, subscription_start, upgrade, downgrade, cancellation
  plan          VARCHAR(20),
  -- NULL em eventos de trial; Basic / Standard / Premium / Family nos demais
  mrr_impact    NUMERIC(10, 2) NOT NULL DEFAULT 0,
  cancel_reason VARCHAR(50)
  -- preenchido apenas quando event_type = 'cancellation'
);

CREATE TABLE usage_events (
  usage_id          INTEGER PRIMARY KEY,
  user_id           INTEGER NOT NULL REFERENCES users(user_id),
  session_date      DATE NOT NULL,
  device            VARCHAR(20) NOT NULL,
  genre             VARCHAR(30) NOT NULL,
  watch_minutes     INTEGER NOT NULL,
  completed_content BOOLEAN NOT NULL
);

CREATE INDEX idx_subscription_events_user_id ON subscription_events(user_id);
CREATE INDEX idx_usage_events_user_id ON usage_events(user_id);
