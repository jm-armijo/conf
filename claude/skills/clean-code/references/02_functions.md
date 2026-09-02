# Functions

## Small and Do One Thing (Single Responsibility)
Exception: Facade/orchestration methods.
**Bad:**
```ruby
def process_order(order)
  if order.valid?
    Payment.charge(order.amount)
    Email.send(order.user)
  end
end
```
**Good:**
```ruby
def process_order(order)
  return unless order.valid?
  charge_order(order)
  notify_user(order)
end
```

## Limit Function Arguments
Exception: Configuration/DTO initialization (use `**kwargs`).
**Bad:**
```ruby
def create_user(first, last, email, age, role)
end
```
**Good:**
```ruby
def create_user(first:, last:, email:, age:, role:)
end
```

## Command Query Separation (CQS)
Exception: Popping/dequeuing items.
**Bad:**
```ruby
def set_and_check(attr, val)
  @data[attr] = val
  @data[attr] == val
end
```
**Good:**
```ruby
def set_attr(attr, val)
  @data[attr] = val
end
```
