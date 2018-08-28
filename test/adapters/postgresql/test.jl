using TestOcto.Adapters.PostgreSQL
using Test

@test to_sql([SELECT (TRUE, FALSE)]) == "SELECT TRUE, FALSE"

Repo.debug_sql()

Repo.connect(
    adapter = TestOcto.Adapters.PostgreSQL,
    dbname = "postgresqltest",
    user = "postgres",
)

Repo.execute([DROP TABLE IF EXISTS :test1])
Repo.execute(Raw("""
CREATE TABLE IF NOT EXISTS test1 (a boolean, b text)
"""))
