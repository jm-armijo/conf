# Formatting

## Vertical and Horizontal Proximity
Exception: Global configuration constants.
**Bad:**
```ruby
def calculate
  total = 0
  # 50 lines of unrelated logic
  total += 10
end
```
**Good:**
```ruby
def calculate
  # unrelated logic
  total = 0
  total += 10
end
```
