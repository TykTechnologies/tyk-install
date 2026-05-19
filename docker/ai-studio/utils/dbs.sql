CREATE DATABASE tyk_ai_microgateway;

GRANT ALL PRIVILEGES ON DATABASE tyk_ai_microgateway TO tykuser;

\connect tyk_ai_microgateway

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'blob') THEN
    CREATE DOMAIN blob AS bytea;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'string') THEN
    CREATE DOMAIN string AS text;
  END IF;
END
$$;
