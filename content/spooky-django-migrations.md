Status: draft
Title: Spooky Django migrations
Date: 2024-11-13 21:35
Modified: 2024-11-13 21:35
Category: Python
Tags: python, django
Slug: spooky-django-migrations
Authors: Sam Dudley
Summary: Short version for index and feeds

I recently came across an interesting and spooky problem with Django migrations at my
`$DAY_JOB`.

I was adding a new Django app to the project (let's call it `foo_app`) and was deploying
the change to our various environments.

On this project we have 4 environments:

- local
- dev
- staging
- prod

My changes included a couple of new Django migrations within the new app.

```text
my_project/
    foo_app/
        migrations/
            0001_add_some_model.py
            0002_change_some_fields.py
```

When I tested my changes on locally, everything worked as expected. I successfully
deployed my changes to the `dev` environment, and found no issues in testing.

After a successful test on `dev`, I merged my code into our `main` branch which triggers
an automatic deployment to the `staging` environment. I went to test my changes on
`staging` and immediately hit a server 500 error. I checked in our error tracking and
found that the error was Django complaining that there was a missing database table that
should have been created by the new migrations.

My first thought was that for some reason the `migrate` command hadn't been run on
deployment and the migrations hadn't been applied. I SSHed onto the `staging` server
and started to take a look. I began by trying to run the `migrate` command manually and
checking for errors. I ran `python manage.py migrate` and Django informed me that there
were no migrations to run and we were up to date.

Next, I took a look at the `django_migrations` table to check that my migrations had
been recorded in there. I connected to our PostgreSQL database using `psql` and ran the
following query:

```sql
SELECT * FROM django_migrations WHERE app = 'foo_app';
```

To my surprise, the query returned 9 rows, none of which were related to the migrations
I was expecting to see.

```text
0001_[...].py
0002_[...].py
0003_[...].py
...
0009_[...].py
```

It was at this point that I realised what was happening. These migrations were from an
old app in this project, that had used the same name as our new app (`foo_app` in
this example).

# FIXME: first review up to here

The old app had 9 migrations and our new app had 2 migrations. When we ask Django to
apply our new migrations, it checks the `django_migrations` table and sees that `0001`
and `0002` have already been applied, even though they refer to the old Django app.

The reason we didn't see this problem locally, or on the `dev` environment, must be
because those environments have been recreated from scratch since that old Django app
had been deleted. However, the `staging` environment hadn't been recreated since and the
database hadn't been cleaned up when the Django app was removed.

Now that I knew what the problem was, I hopped onto the `prod` environment and confirmed
the same issue was present there, which it was, and began to formulate a plan.

I started reading the Django documentation for the
[`migrate`](https://docs.djangoproject.com/en/5.1/ref/django-admin/#migrate) command and
found the
[`--fake`](https://docs.djangoproject.com/en/5.1/ref/django-admin/#cmdoption-migrate-fake)
flag which looks like it could be useful. What the `--fake` flag will do is allow me to
reverse the migrations of `new_app` but without actually trying to unapply the changes
in the file. The reason this is important is Django will unapply the migrations file
that currently live in my application, and as these haven't actually been ran, the
reverse migrate will fail, hence we need to `--fake` the work. I proceeded to use
`--fake` to reverse the migrations of `new_app` with the following command:

```bash
python manage.py migrate new_app zero --fake
```

This command proceeded to unapply the migrations that I had for `new_app` without doing
performing any changes. In practice this meant that the 2 rows for my `0001` and `0002`
migrations were removed from the `django_migrations` table, leaving me in the following
state.

```text
0003_[...].py
0004_[...].py
0005_[...].py
...
0009_[...].py
```

As you can see, there are no records for `0001` or `0002` migrations. This can be
followed up with running the `migrate` command forwards for `new_app`, and my migrations
should be applied.

```bash
python manage.py migrate new_app
```

It's important to note that this will only work if there are no conflicts with the
previous, redundant tables which haven't been cleaned up. In my case I had chosen
different names for my models so there were no conflicts.

This now leaves me in the following state:

```text
0001_[...].py  # current
0002_[...].py  # current
0003_[...].py  # legacy
0004_[...].py  # legacy
0005_[...].py  # legacy
...
0009_[...].py  # legacy
```

My app is now working as expected, but I still have tables and records in the
`django_migrations` table laying around that I don't need.

I worked out which tables were no longer needed and dropped them

```sql
DROP TABLE new_app_old_table_1, new_app_old_table_2;
```

and tidied up the `django_migrations` table

```sql
DELETE FROM django_migrations
WHERE app = 'new_app' AND name !~ '^000(1|2)_.+';
```

I performed these actions on `staging` and checked that the same actions would be valid
on `prod`. It was at this point that I realised that the `migrate --fake` step wasn't
needed and that I only needed to drop the tables and tidy up the migrations table before
running the current migrations. This also avoids the issue of trying to run conflicting
migrations after faking backwards migrations and the SQL command to tidy up the
`django_migrations` table is simpler as we can remove all rows first before our new
migrations are run.

As the `migrate` command is ran as part of deployment, this became my plan for `prod`
and my final solution:

1. Connect to the `prod` database
2. Drop legacy, redundant tables
3. Delete legacy migration records from the `django_migrations` table
4. Deploy `main` to `prod` which will run new migrations for `new_app`

I performed this plan, prod deployed successfully, and I confirmed anything was right
with testing.
