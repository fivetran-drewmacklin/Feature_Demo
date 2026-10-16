select
    refunds.refund_id,
    refunds.payment_id,
    refunds.invoice_id as refund_invoice_id,
    payments.invoice_id as payment_invoice_id,
    refunds.amount_cents as refund_amount_cents,
    payments.amount_cents as payment_amount_cents,
    refunds.currency as refund_currency,
    payments.currency as payment_currency,
    refunds.refunded_at,
    payments.paid_at
from {{ ref('stg_billing__refunds') }} as refunds
inner join {{ ref('stg_billing__payments') }} as payments using (payment_id)
where payments.status <> 'succeeded'
   or refunds.invoice_id <> payments.invoice_id
   or refunds.amount_cents > payments.amount_cents
   or refunds.currency <> payments.currency
   or (refunds.status = 'succeeded' and refunds.refunded_at < payments.paid_at)
