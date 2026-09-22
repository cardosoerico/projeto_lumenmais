-- Schema do projeto LumenMais
-- Criação das tabelas base do modelo de dados

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
