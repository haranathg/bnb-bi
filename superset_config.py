import os
import jwt
from flask import request
from flask_appbuilder.security.manager import AUTH_DB
from superset.security import SupersetSecurityManager

# -------------------------------------------------------------
# Basic Configuration
# -------------------------------------------------------------
ROW_LIMIT = 5000
SUPERSET_WEBSERVER_PORT = 8088
SECRET_KEY = os.getenv("SUPERSET_SECRET_KEY", "change_me")

# Metadata DB (Neon)
SQLALCHEMY_DATABASE_URI = os.getenv("SUPERSET_DATABASE_URI")

# -------------------------------------------------------------
# Hybrid Auth: JWT (for portal) + Local login (for direct users)
# -------------------------------------------------------------
AUTH_TYPE = AUTH_DB
PUBLIC_ROLE_LIKE_GAMMA = False
JWT_SECRET = os.getenv("SUPERSET_JWT_SECRET", "replace_with_strong_secret")

class HybridSecurityManager(SupersetSecurityManager):
    def get_user_from_request(self, request):
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        if not token:
            return None
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
            username = payload.get("username")
            if not username:
                return None
            user = self.find_user(username=username)
            if not user:
                user = self.add_user(
                    username=username,
                    first_name=payload.get("first_name", ""),
                    last_name=payload.get("last_name", ""),
                    email=payload.get("email", f"{username}@example.com"),
                    role=self.find_role("AnalystLite"),
                )
            return user
        except Exception as ex:
            print(f"JWT auth failed ({ex}); falling back to local login.")
            return None

CUSTOM_SECURITY_MANAGER = HybridSecurityManager

# -------------------------------------------------------------
# Misc
# -------------------------------------------------------------
CACHE_DEFAULT_TIMEOUT = 60
DATA_CACHE_CONFIG = None
