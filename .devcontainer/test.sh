http POST localhost:8000/echo \
    users:='[
        {"id": 1, "name": "bob", "email": "bob@example.com"},
        {"id": 2, "name": "alice", "email": "alice@example.com"},
        {"id": 3, "name": "charlie", "email": "charlie@example.com"}
    ]' \
    teams:='[
        {
            "team_name": "Alpha",
            "members": [
                {"id": 4, "name": "david", "email": "david@example.com"},
                {"id": 5, "name": "eve", "email": "eve@example.com"}
            ]
        },
        {
            "team_name": "Beta",
            "members": [
                {"id": 6, "name": "frank", "email": "frank@example.com"},
                {"id": 7, "name": "grace", "email": "grace@example.com"}
            ]
        }
    ]' \
    organizations:='[
        {
            "org_id": 1,
            "name": "TechCorp",
            "departments": [
                {
                    "dept_id": 101,
                    "name": "Engineering",
                    "employees": [
                        {"id": 8, "name": "henry", "email": "henry@techcorp.com"},
                        {"id": 9, "name": "isabel", "email": "isabel@techcorp.com"}
                    ]
                },
                {
                    "dept_id": 102,
                    "name": "Marketing",
                    "employees": [
                        {"id": 10, "name": "jack", "email": "jack@techcorp.com"},
                        {"id": 11, "name": "kate", "email": "kate@techcorp.com"}
                    ]
                }
            ]
        },
        {
            "org_id": 2,
            "name": "FinGroup",
            "departments": [
                {
                    "dept_id": 201,
                    "name": "Finance",
                    "employees": [
                        {"id": 12, "name": "leo", "email": "leo@fingroup.com"},
                        {"id": 13, "name": "mia", "email": "mia@fingroup.com"}
                    ]
                }
            ]
        }
    ]'
