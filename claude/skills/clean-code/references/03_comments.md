# Comments

**The default is zero comments.** A comment is a confession that the code failed
to say it. Reach for a rename, an extracted method, or a better structure first;
write the comment only when none of those can carry the meaning.

Before writing one, ask: *would a rename or an extraction delete this?* If yes,
do that instead.

## Never Restate The Name Below It
The most common failure. If the comment paraphrases the identifier under it,
delete the comment — it cannot drift out of date if it does not exist.
**Bad:**
```ruby
# One run of text under a single foreground/background pair.
Run = Struct.new(:foreground, :background, :text)

# A state's committed expectation.
class Expectation
```
**Good:**
```ruby
Run = Struct.new(:foreground, :background, :text)

class Expectation
```

## No Headers, Banners, Or Doc Lines
No file-summary headers, no `# ---- Section ----` banners, no a-line-per-class
documentation. They are pure restatement and they rot silently.

## Explain "Why", Not "What"
Exception: Regex, API contracts, bug workarounds.

The surviving cases are narrow: a non-obvious constraint, an external-tool quirk,
or a rejected alternative that looks correct. Budget roughly one comment per 50
lines; exceeding it means restructure, not explain.
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
