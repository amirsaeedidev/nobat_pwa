-- Final relational integrity and write-surface hardening.

-- Appointment service snapshots are written only inside the booking RPC.
revoke insert, update, delete on public.appointment_services from authenticated;

-- Ensure financial links cannot point at another employee's ledger row.
alter table public.employee_finance_entries
  add constraint employee_finance_entries_business_employee_id_key unique (business_id, employee_id, id);

alter table public.employee_wallet_transactions
  add constraint employee_wallet_transactions_business_employee_id_key unique (business_id, employee_id, id);

alter table public.employee_wallet_transactions
  drop constraint if exists employee_wallet_transactions_business_id_finance_entry_id_fkey;
alter table public.employee_wallet_transactions
  add constraint employee_wallet_transactions_finance_entry_same_employee_fkey
  foreign key (business_id, employee_id, finance_entry_id)
  references public.employee_finance_entries (business_id, employee_id, id)
  on delete restrict;

alter table public.employee_finance_entries
  drop constraint if exists employee_finance_entries_business_id_reverses_entry_id_fkey;
alter table public.employee_finance_entries
  add constraint employee_finance_entries_reversal_same_employee_fkey
  foreign key (business_id, employee_id, reverses_entry_id)
  references public.employee_finance_entries (business_id, employee_id, id)
  on delete restrict;

alter table public.employee_settlements
  drop constraint if exists employee_settlements_business_id_wallet_transaction_id_fkey;
alter table public.employee_settlements
  add constraint employee_settlements_wallet_same_employee_fkey
  foreign key (business_id, employee_id, wallet_transaction_id)
  references public.employee_wallet_transactions (business_id, employee_id, id)
  on delete restrict;

create unique index if not exists service_categories_business_name_ci_unique
  on public.service_categories (business_id, lower(trim(name)));
