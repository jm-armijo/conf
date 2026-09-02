# Error Handling

## Prefer Exceptions to Error Codes
Exception: Strict API contracts requiring status codes.
**Bad:**
```ruby
def load_file(path)
  return -1 unless File.exist?(path)
  File.read(path)
end
```
**Good:**
```ruby
def load_file(path)
  raise Errno::ENOENT unless File.exist?(path)
  File.read(path)
end
```

## Don't Pass or Return Null (nil)
Exception: Query methods where missing records are expected (e.g., `find_by`).
**Bad:**
```ruby
def user_plan(user)
  return nil if user.subscription.nil?
  user.subscription.plan
end
```
**Good:**
```ruby
def user_plan(user)
  user.subscription&.plan || NullPlan.new
end
```
