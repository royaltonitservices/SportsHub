# SportsHub API Endpoints

Complete reference for all backend API endpoints.

## Authentication Endpoints

### POST /auth/signup
Register a new user account
- Body: `{ email, username, password, display_name, date_of_birth }`
- Returns: JWT token
- Creates default sport profiles for all sports

### POST /auth/login
Login with OAuth2 form (username=email, password)
- Returns: JWT token

### POST /auth/login/json
Login with JSON body (for mobile apps)
- Body: `{ email, password }`
- Returns: JWT token

## User Management Endpoints

### GET /users/me
Get current user's profile
- Auth: Required
- Returns: Full user profile

### GET /users/{user_id}
Get user by ID
- Auth: Required
- Returns: User profile

### GET /users/username/{username}
Get user by username
- Auth: Required
- Returns: User profile

### GET /users?query={search}
Search users by username or display name
- Auth: Required
- Query params: `query`, `limit` (default 20)
- Returns: List of users

## Sport Profile Endpoints

### GET /sports/profiles
Get all sport profiles for current user
- Auth: Required
- Returns: List of sport profiles

### GET /sports/profiles/{sport}
Get specific sport profile
- Auth: Required
- Path: sport (basketball, football, soccer, tennis)
- Returns: Sport profile

### GET /sports/profiles/user/{user_id}
Get sport profiles for a specific user
- Auth: Required
- Returns: List of sport profiles

## Friend System Endpoints

### POST /friends/request
Send friend request
- Auth: Required
- Body: `{ target_user_id }`
- Returns: Friendship object

### POST /friends/accept/{friendship_id}
Accept friend request
- Auth: Required (must be recipient)
- Returns: Updated friendship

### POST /friends/decline/{friendship_id}
Decline friend request
- Auth: Required (must be recipient)
- Returns: Success message

### DELETE /friends/{friendship_id}
Remove friend (unfriend)
- Auth: Required (must be participant)
- Returns: Success message

### GET /friends/list
Get all accepted friendships
- Auth: Required
- Returns: List of friendships

### GET /friends/requests/pending
Get all pending requests (sent and received)
- Auth: Required
- Returns: List of pending friendships

### GET /friends/requests/received
Get pending requests received
- Auth: Required
- Returns: List of received requests

## Messaging Endpoints (Friends-Only)

### POST /messages/send
Send direct message to a friend
- Auth: Required
- Body: `{ receiver_id, content }`
- Requires: Active friendship
- Returns: Message object

### GET /messages/conversation/{user_id}
Get message history with a user
- Auth: Required
- Requires: Active friendship
- Query params: `limit` (default 50)
- Returns: List of messages (oldest first)
- Side effect: Marks messages as read

### GET /messages/conversations
Get all conversations with last message preview
- Auth: Required
- Returns: List with friend info, last message, unread count

### DELETE /messages/{message_id}
Delete message (soft delete)
- Auth: Required (must be sender or receiver)
- Returns: Success message

## Challenge System Endpoints

### POST /challenges/create
Create a new challenge
- Auth: Required
- Body: `{ sport, opponent_id }`
- Requires: Active friendship, both have sport profiles
- Returns: Challenge object

### POST /challenges/{challenge_id}/accept
Accept a challenge
- Auth: Required (must be opponent)
- Returns: Updated challenge

### POST /challenges/{challenge_id}/decline
Decline a challenge
- Auth: Required (must be opponent)
- Returns: Success message

### POST /challenges/{challenge_id}/complete
Complete challenge and record result
- Auth: Required (must be participant)
- Body: `{ winner_id, score_data }`
- Updates sport profile stats
- Returns: Success with winner_id

### GET /challenges/my-challenges
Get all challenges for current user
- Auth: Required
- Query params: `status_filter` (pending, accepted, declined, completed)
- Returns: List of challenges

### GET /challenges/{challenge_id}
Get challenge details
- Auth: Required
- Returns: Challenge object

## Posts Feed Endpoints

### POST /posts/create
Create a new post
- Auth: Required
- Body: `{ content, sport? }`
- Returns: Post object

### GET /posts/feed
Get posts feed
- Auth: Required
- Query params: `sport`, `skip`, `limit` (default 20)
- Returns: List of posts (newest first)

### GET /posts/{post_id}
Get specific post
- Auth: Required
- Returns: Post object

### GET /posts/user/{user_id}
Get posts by user
- Auth: Required
- Query params: `skip`, `limit` (default 20)
- Returns: List of posts

### POST /posts/{post_id}/like
Like a post
- Auth: Required
- Returns: Success message

### DELETE /posts/{post_id}/like
Unlike a post
- Auth: Required
- Returns: Success message

### DELETE /posts/{post_id}
Delete post (author only)
- Auth: Required (must be author)
- Returns: Success message

## Clips Feed Endpoints

### POST /clips/create
Create a new clip
- Auth: Required
- Body: `{ sport, title, video_url?, duration }`
- Returns: Clip object

### GET /clips/feed
Get clips feed
- Auth: Required
- Query params: `sport`, `skip`, `limit` (default 20)
- Returns: List of clips (newest first)

### GET /clips/{clip_id}
Get specific clip
- Auth: Required
- Side effect: Increments view count
- Returns: Clip object

### GET /clips/user/{user_id}
Get clips by user
- Auth: Required
- Query params: `skip`, `limit` (default 20)
- Returns: List of clips

### GET /clips/trending
Get trending clips
- Auth: Required
- Query params: `sport`, `limit` (default 20)
- Sorting: views + (likes * 5)
- Returns: List of clips

### POST /clips/{clip_id}/like
Like a clip
- Auth: Required
- Returns: Success message

### DELETE /clips/{clip_id}/like
Unlike a clip
- Auth: Required
- Returns: Success message

### DELETE /clips/{clip_id}
Delete clip (author only)
- Auth: Required (must be author)
- Returns: Success message

## Admin Endpoints (Admin Only)

### GET /admin/users
Get list of all users
- Auth: Admin required
- Query params: `skip`, `limit` (default 100), `account_status`
- Returns: List of users

### GET /admin/users/{user_id}
Get detailed user information
- Auth: Admin required
- Returns: Full user profile

### POST /admin/users/{user_id}/suspend
Suspend user account
- Auth: Admin required
- Body: `{ reason }`
- Logs admin action
- Returns: Success message

### POST /admin/users/{user_id}/ban
Ban user permanently
- Auth: Admin required
- Body: `{ reason }`
- Logs admin action
- Returns: Success message

### POST /admin/users/{user_id}/shadow-ban
Shadow ban user
- Auth: Admin required
- Body: `{ reason }`
- Logs admin action
- Returns: Success message

### POST /admin/users/{user_id}/reactivate
Reactivate suspended/banned user
- Auth: Admin required
- Logs admin action
- Returns: Success message

### GET /admin/actions
Get recent admin actions
- Auth: Admin required
- Query params: `limit` (default 100)
- Returns: List of admin actions with usernames

### GET /admin/stats
Get platform statistics
- Auth: Admin required
- Returns: User counts, content counts, moderation stats

## Moderation Endpoints

### POST /moderation/report
Report content for moderation
- Auth: Required
- Body: `{ content_type, content_id, reason }`
- Valid types: post, clip, message, user
- Returns: Success message

### GET /moderation/flags
Get all moderation flags (admin only)
- Auth: Admin required
- Query params: `status_filter`, `content_type`, `limit` (default 100)
- Returns: List of flags

### POST /moderation/flags/{flag_id}/resolve
Resolve moderation flag (admin only)
- Auth: Admin required
- Body: `{ action }` (remove, dismiss, warn)
- Logs admin action
- Returns: Success message

### POST /moderation/flags/{flag_id}/dismiss
Dismiss moderation flag (admin only)
- Auth: Admin required
- Logs admin action
- Returns: Success message

## Health & Info Endpoints

### GET /
API information
- No auth required
- Returns: API name, version, docs URL

### GET /health
Health check
- No auth required
- Returns: `{ status: "healthy" }`

---

## Authentication

All protected endpoints require a Bearer token in the Authorization header:

```
Authorization: Bearer <jwt_token>
```

Get the token from `/auth/login` or `/auth/signup`.

## Admin Account (2-Key System)

Admin access requires **BOTH** credentials to match exactly:
- **Email**: aarushkhanna11@gmail.com
- **Password**: $81Admin

⚠️ **Important**: The admin role is only granted when BOTH the email AND password match. This 2-key system ensures that only authorized users can access admin functionality.

## Error Responses

All endpoints return standard HTTP status codes:

- 200: Success
- 201: Created
- 400: Bad request (validation error)
- 401: Unauthorized (missing or invalid token)
- 403: Forbidden (insufficient permissions)
- 404: Not found
- 500: Internal server error

Error format:
```json
{
  "detail": "Error message here"
}
```
