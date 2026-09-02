# Unit Tests

## One Assert per Test / Single Concept
Exception: Heavy E2E/UI tests with expensive setup.
**Bad:**
```ruby
def test_user
  user = User.create(name: "John")
  assert_equal "John", user.name
  assert user.active?
end
```
**Good:**
```ruby
def test_user_name
  user = User.create(name: "John")
  assert_equal "John", user.name
end

def test_user_active
  user = User.create(name: "John")
  assert user.active?
end
```
