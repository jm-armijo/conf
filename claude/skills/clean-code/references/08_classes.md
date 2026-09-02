# Classes

## SRP and Cohesion
Exception: ActiveRecord models naturally accumulate database logic (mitigate with Service Objects).
**Bad:**
```ruby
class User
  def save_to_db; end
  def generate_pdf; end
end
```
**Good:**
```ruby
class User
  def save_to_db; end
end

class UserPdfGenerator
  def generate(user); end
end
```
