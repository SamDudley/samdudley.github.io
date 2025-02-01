Status: published
Title: Bulk upserts in Django
Date: 2025-01-27 21:13
Modified: 2025-02-01 20:37
Category: Python
Tags: python, django, til
Slug: til-bulk-upserts-in-django
Authors: Sam Dudley
Summary: TIL that you can do bulk upserts in Django

```python
class Cake(models.Model):
    sku = models.CharField(max_length=8, unique=True)
    name = models.CharField(max_length=64)

Cake.objects.create(sku="CAKE0001", name="Coffee Cake")

cakes = [
    Cake(sku="CAKE0001", name="Deluxe Coffee Cake"),
    Cake(sku="CAKE0002", name="Lemon Drizzle Cake"),
]

# Bulk upsert
Cake.objects.bulk_create(
    cakes,
    unique_fields=["sku"],
    update_conflicts=True,
    updates_fields=["name"],
)

assert Cake.objects.count() == 2
assert Cake.objects.get(sku="CAKE0001").name == "Deluxe Coffee Cake"
```

Is roughly equivalent to

```sql
INSERT INTO cake (sku name)
    VALUES ('CAKE0001', 'Coffee Cake');

INSERT INTO cake (sku, name)
    VALUES ('CAKE0001', 'Deluxe Coffee Cake'), ('CAKE0002', 'Lemon Drizzle Cake')
    ON CONFLICT (sku) DO UPDATE SET name = EXCLUDED.name;
```

Here are the [docs](https://docs.djangoproject.com/en/5.1/ref/models/querysets/#bulk-create).
