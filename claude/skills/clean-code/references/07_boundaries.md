# Boundaries

## Encapsulate Third-Party Boundaries
Exception: Standard language libraries or core frameworks (e.g., ActiveRecord).
**Bad:**
```ruby
# Scattered across 20 files
Stripe::Charge.create(amount: 1000, source: token)
```
**Good:**
```ruby
# Wrapped in dedicated service
PaymentProcessor.charge(amount: 1000, token: token)
```
