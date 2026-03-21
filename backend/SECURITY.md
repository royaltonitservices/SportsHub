# SportsHub Security Documentation

## Admin Access Control - 2-Key System

### Overview

SportsHub uses a **2-key authentication system** for admin access. This means that admin privileges are only granted when **BOTH** the email AND password match the predefined admin credentials.

### Admin Credentials

- **Email**: `aarushkhanna11@gmail.com`
- **Password**: `$81Admin`

### How It Works

#### During Signup (routers/auth.py)
```python
# Check if admin credentials (2-key system: BOTH email AND password must match)
is_admin = (user_data.email == ADMIN_EMAIL and user_data.password == ADMIN_PASSWORD)
user_role = models.UserRole.ADMIN if is_admin else models.UserRole.USER
```

#### During Login
The system verifies the user's stored role in the database. The role was set during signup based on the 2-key check.

### Security Benefits

1. **Email-Only Protection**: Even if someone knows the admin email, they cannot gain admin access without the exact password.

2. **Password-Only Protection**: Even if someone knows the admin password, they cannot gain admin access without the admin email.

3. **Combined Security**: Both credentials must match exactly for admin role assignment.

### Code Locations

**iOS App** - `SportsHub/SessionManager.swift`:
```swift
// Line 43 - Login check
let isAdminUser = (email == adminEmail && password == adminPassword)

// Line 70 - Signup check
let isAdminUser = (email == adminEmail && password == adminPassword)
```

**Backend** - `backend/routers/auth.py`:
```python
# Lines 16-17 - Admin credentials
ADMIN_EMAIL = "aarushkhanna11@gmail.com"
ADMIN_PASSWORD = "$81Admin"

# Lines 48-50 - Signup check
is_admin = (user_data.email == ADMIN_EMAIL and user_data.password == ADMIN_PASSWORD)
user_role = models.UserRole.ADMIN if is_admin else models.UserRole.USER
```

### Important Notes

⚠️ **Case Sensitive**: Both email and password are case-sensitive
⚠️ **Exact Match**: No partial matches - both must be exactly correct
⚠️ **Role Immutable**: Once a user is created, their role cannot be changed (prevents privilege escalation)
⚠️ **Single Admin**: Only one admin account exists with these exact credentials

### Testing Admin Access

#### Valid Admin Signup:
```json
POST /auth/signup
{
  "email": "aarushkhanna11@gmail.com",
  "password": "$81Admin",
  "username": "admin",
  "display_name": "Admin User",
  "date_of_birth": "1990-01-01"
}
```
**Result**: User created with `role: ADMIN`

#### Invalid Admin Attempt (Wrong Password):
```json
POST /auth/signup
{
  "email": "aarushkhanna11@gmail.com",
  "password": "wrongpassword",
  "username": "notadmin",
  "display_name": "Regular User",
  "date_of_birth": "1990-01-01"
}
```
**Result**: User created with `role: USER` (not admin)

#### Invalid Admin Attempt (Wrong Email):
```json
POST /auth/signup
{
  "email": "other@gmail.com",
  "password": "$81Admin",
  "username": "notadmin2",
  "display_name": "Regular User",
  "date_of_birth": "1990-01-01"
}
```
**Result**: User created with `role: USER` (not admin)

### Additional Security Features

1. **JWT Authentication**: All protected endpoints require valid JWT token
2. **Role-Based Access Control**: Admin endpoints check for ADMIN role
3. **Password Hashing**: Passwords stored with bcrypt (cost factor 12)
4. **Age Verification**: Users must be 13+ to create account
5. **Account Status**: Suspended/banned users cannot access system
6. **Audit Trail**: All admin actions are logged in AdminAction table

### Admin Endpoint Protection

All admin endpoints use the `get_current_admin_user` dependency:

```python
@router.get("/admin/users")
async def get_all_users(
    admin: models.User = Depends(get_current_admin_user)  # Checks for ADMIN role
):
    # Only accessible if user.role == UserRole.ADMIN
    ...
```

### Future Enhancements

Consider implementing:
- [ ] Multi-factor authentication for admin
- [ ] Admin session timeout (shorter than regular users)
- [ ] IP whitelist for admin access
- [ ] Admin action approval workflow
- [ ] Rotating admin credentials
- [ ] Admin access logs with email alerts

---

**Last Updated**: 2026-03-07
**Security Level**: 2-Key Authentication System
**Admin Email**: aarushkhanna11@gmail.com
