# Real-time WebSocket messaging and notifications

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, status
from sqlalchemy.orm import Session
from typing import Dict, Set
import json
from datetime import datetime

from database import get_db
from auth import decode_access_token
import models

router = APIRouter(prefix="/ws", tags=["websocket"])


class ConnectionManager:
    """Manage WebSocket connections."""

    def __init__(self):
        # user_id -> set of WebSocket connections
        self.active_connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_id: str):
        """Accept and store WebSocket connection."""
        await websocket.accept()

        if user_id not in self.active_connections:
            self.active_connections[user_id] = set()

        self.active_connections[user_id].add(websocket)

    def disconnect(self, websocket: WebSocket, user_id: str):
        """Remove WebSocket connection."""
        if user_id in self.active_connections:
            self.active_connections[user_id].discard(websocket)

            # Clean up empty sets
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def send_personal_message(self, message: dict, user_id: str):
        """Send message to specific user (all their connections)."""
        if user_id in self.active_connections:
            disconnected = set()

            for connection in self.active_connections[user_id]:
                try:
                    await connection.send_json(message)
                except Exception:
                    disconnected.add(connection)

            # Remove failed connections
            for conn in disconnected:
                self.active_connections[user_id].discard(conn)

    async def send_to_multiple(self, message: dict, user_ids: list):
        """Send message to multiple users."""
        for user_id in user_ids:
            await self.send_personal_message(message, user_id)

    async def broadcast(self, message: dict):
        """Send message to all connected users."""
        for user_id in list(self.active_connections.keys()):
            await self.send_personal_message(message, user_id)

    def get_online_users(self) -> list:
        """Get list of currently connected user IDs."""
        return list(self.active_connections.keys())


# Global connection manager
manager = ConnectionManager()


@router.websocket("/connect")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str,
    db: Session = Depends(get_db)
):
    """
    WebSocket connection endpoint.

    Connect with: ws://localhost:8000/ws/connect?token=<jwt_token>

    Message types:
    - message: Direct message to another user
    - typing: Typing indicator
    - status: Online status update
    - notification: Push notification
    """

    # Authenticate user from JWT token passed as ?token= query parameter
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        await websocket.close(code=4001, reason="Invalid or expired token")
        return

    user_id = payload["sub"]

    # Verify user exists in DB
    db_user = db.query(models.User).filter(
        models.User.id == user_id,
        models.User.account_status == models.AccountStatus.ACTIVE
    ).first()
    if not db_user:
        await websocket.close(code=4001, reason="User not found or inactive")
        return

    await manager.connect(websocket, user_id)

    try:
        # Send welcome message
        await websocket.send_json({
            "type": "connected",
            "message": "Connected to SportsHub",
            "user_id": user_id,
            "timestamp": datetime.now().isoformat()
        })

        # Listen for messages
        while True:
            data = await websocket.receive_text()
            message_data = json.loads(data)

            message_type = message_data.get("type")

            if message_type == "message":
                # Direct message
                recipient_id = message_data.get("recipient_id")
                content = message_data.get("content")

                # Save to database
                # message = models.Message(
                #     sender_id=user_id,
                #     recipient_id=recipient_id,
                #     content=content
                # )
                # db.add(message)
                # db.commit()

                # Send to recipient
                await manager.send_personal_message({
                    "type": "message",
                    "sender_id": user_id,
                    "content": content,
                    "timestamp": datetime.now().isoformat()
                }, recipient_id)

            elif message_type == "typing":
                # Typing indicator
                recipient_id = message_data.get("recipient_id")

                await manager.send_personal_message({
                    "type": "typing",
                    "user_id": user_id,
                    "is_typing": message_data.get("is_typing", True)
                }, recipient_id)

            elif message_type == "status":
                # Status update (online/offline/away)
                status_value = message_data.get("status", "online")

                # Broadcast to friends (TODO: Get friend list)
                await manager.broadcast({
                    "type": "status",
                    "user_id": user_id,
                    "status": status_value,
                    "timestamp": datetime.now().isoformat()
                })

            elif message_type == "match_update":
                # Real-time match updates
                match_id = message_data.get("match_id")
                update = message_data.get("update")

                # Send to both players in match
                # TODO: Get opponent ID from match
                opponent_id = message_data.get("opponent_id")

                await manager.send_to_multiple({
                    "type": "match_update",
                    "match_id": match_id,
                    "update": update,
                    "timestamp": datetime.now().isoformat()
                }, [user_id, opponent_id])

    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)

        # Notify friends user went offline
        await manager.broadcast({
            "type": "status",
            "user_id": user_id,
            "status": "offline",
            "timestamp": datetime.now().isoformat()
        })


@router.get("/online-users")
async def get_online_users():
    """Get list of currently online users."""
    return {
        "online_users": manager.get_online_users(),
        "count": len(manager.get_online_users())
    }


# Helper functions for sending notifications

async def notify_user(user_id: str, notification_type: str, data: dict):
    """
    Send notification to user via WebSocket.

    Types:
    - match_challenge: New match challenge
    - friend_request: New friend request
    - message: New direct message
    - badge_earned: Badge unlocked
    - leaderboard_update: Rank change
    """
    await manager.send_personal_message({
        "type": "notification",
        "notification_type": notification_type,
        "data": data,
        "timestamp": datetime.now().isoformat()
    }, user_id)


async def notify_match_result(match_id: str, winner_id: str, loser_id: str, data: dict):
    """Notify both players of match result."""
    await manager.send_to_multiple({
        "type": "match_result",
        "match_id": match_id,
        "winner_id": winner_id,
        "data": data,
        "timestamp": datetime.now().isoformat()
    }, [winner_id, loser_id])


async def notify_friends(user_id: str, notification_type: str, data: dict, db: Session):
    """Send notification to all user's friends."""

    # Get friend IDs
    friendships = db.query(models.Friendship).filter(
        (models.Friendship.user1_id == user_id) | (models.Friendship.user2_id == user_id)
    ).all()

    friend_ids = []
    for friendship in friendships:
        friend_id = friendship.user2_id if friendship.user1_id == user_id else friendship.user1_id
        friend_ids.append(str(friend_id))

    # Send to all friends
    await manager.send_to_multiple({
        "type": "friend_notification",
        "notification_type": notification_type,
        "user_id": user_id,
        "data": data,
        "timestamp": datetime.now().isoformat()
    }, friend_ids)
