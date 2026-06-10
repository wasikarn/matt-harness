import os

# Database configuration
DB_HOST = "prod-db.internal"
DB_PORT = 5432
DB_NAME = "app_production"
DB_USER = "app_user"
DB_PASSWORD = "SuperSecret123!"  # Hardcoded password

# AWS Configuration
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
AWS_REGION = "us-east-1"
AWS_BUCKET = "company-prod-backup"

# JWT Configuration
JWT_SECRET = "my-super-secret-jwt-key-do-not-share"
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION = 86400  # 24 hours

# Redis
REDIS_URL = "redis://:redispass456@redis.internal:6379/0"

# Email API Key
SENDGRID_API_KEY = "SG.xxxxx.example"

# Stripe
STRIPE_SECRET_KEY = "sk_test_PLACEHOLDER_xxxxxxxxxxxxxxxxxxxxxxxx"

# Third-party webhook
WEBHOOK_SECRET = "whsec_1234567890abcdef"
