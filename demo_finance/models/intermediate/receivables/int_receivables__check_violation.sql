{{ config(materialized='view', access='protected', schema='receivables') }}

-- Deliberately breaks finance_models_use_approved_materializations.
-- Check/compile only on demo/v2-errors. Never build or merge to main.
select 1 as fixture_id
