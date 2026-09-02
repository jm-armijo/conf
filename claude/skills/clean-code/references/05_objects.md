# Objects and Data Structures

## Hide Internal Structure (Law of Demeter)
Exception: DTOs/Structs explicitly for holding public data.
**Bad:**
```ruby
order.customer.address.zip_code
```
**Good:**
```ruby
order.customer_zip_code
```
