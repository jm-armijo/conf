# Comments

## Explain "Why", Not "What"
Exception: Regex, API contracts, bug workarounds.
**Bad:**
```ruby
# Check if user is active
if user.status == 'active'
```
**Good:**
```ruby
# Legacy check retained for v1 API compatibility
if user.active?
```

## Avoid Commented-Out Code
Exception: Temporary local debug flags.
**Bad:**
```ruby
def tax(amount)
  # amount * 0.15
  amount * 0.20
end
```
**Good:**
```ruby
def tax(amount)
  amount * 0.20
end
```
