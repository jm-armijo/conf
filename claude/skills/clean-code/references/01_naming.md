# Naming Conventions

## Use Intention-Revealing Names
Exception: Common loop iterators (`i`, `j`) in single-line blocks.
**Bad:**
```ruby
d = 0 # elapsed time in days
```
**Good:**
```ruby
elapsed_time_in_days = 0
```

## Avoid Disinformation
Exception: None.
**Bad:**
```ruby
account_list = Account.find(1)
```
**Good:**
```ruby
account = Account.find(1)
```

## Make Meaningful Distinctions
Exception: Domain terms established by ubiquitous language.
**Bad:**
```ruby
class CustomerInfo; end
```
**Good:**
```ruby
class Customer; end
```
