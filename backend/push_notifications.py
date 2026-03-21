# Push Notification Service for SportsHub
# Handles APNs (Apple Push Notification service) and FCM (Firebase Cloud Messaging)

import os
from typing import List, Optional
from datetime import datetime
import httpx
import json


class PushNotificationService:
    """
    Push notification service for iOS (APNs) and Android (FCM).

    Current: Mock service for development
    Production: Integrate with APNs and FCM
    """

    def __init__(self):
        self.apns_enabled = os.getenv("APNS_ENABLED", "false").lower() == "true"
        self.fcm_enabled = os.getenv("FCM_ENABLED", "false").lower() == "true"

        # APNs configuration
        self.apns_key_id = os.getenv("APNS_KEY_ID")
        self.apns_team_id = os.getenv("APNS_TEAM_ID")
        self.apns_bundle_id = os.getenv("APNS_BUNDLE_ID", "com.sportshub.app")

        # FCM configuration
        self.fcm_server_key = os.getenv("FCM_SERVER_KEY")

    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Optional[dict] = None,
        platform: str = "ios"
    ):
        """
        Send push notification to device.

        Args:
            device_token: Device push token
            title: Notification title
            body: Notification body
            data: Custom data payload
            platform: "ios" or "android"
        """

        if platform == "ios":
            await self._send_apns(device_token, title, body, data)
        elif platform == "android":
            await self._send_fcm(device_token, title, body, data)

    async def _send_apns(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Optional[dict] = None
    ):
        """
        Send notification via Apple Push Notification service.

        Production setup:
        1. Create APNs key in Apple Developer portal
        2. Download .p8 key file
        3. Set environment variables:
           - APNS_KEY_ID
           - APNS_TEAM_ID
           - APNS_BUNDLE_ID
        """

        if not self.apns_enabled:
            print(f"[MOCK APNs] Would send to {device_token}: {title} - {body}")
            return

        # Production implementation:
        # from aioapns import APNs, NotificationRequest
        #
        # apns = APNs(
        #     key='/path/to/key.p8',
        #     key_id=self.apns_key_id,
        #     team_id=self.apns_team_id,
        #     topic=self.apns_bundle_id,
        #     use_sandbox=False
        # )
        #
        # notification = NotificationRequest(
        #     device_token=device_token,
        #     message={
        #         'aps': {
        #             'alert': {
        #                 'title': title,
        #                 'body': body
        #             },
        #             'badge': 1,
        #             'sound': 'default'
        #         },
        #         'custom_data': data or {}
        #     }
        # )
        #
        # await apns.send_notification(notification)

    async def _send_fcm(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Optional[dict] = None
    ):
        """
        Send notification via Firebase Cloud Messaging.

        Production setup:
        1. Create Firebase project
        2. Get FCM server key
        3. Set FCM_SERVER_KEY environment variable
        """

        if not self.fcm_enabled:
            print(f"[MOCK FCM] Would send to {device_token}: {title} - {body}")
            return

        # Production implementation:
        # async with httpx.AsyncClient() as client:
        #     response = await client.post(
        #         "https://fcm.googleapis.com/fcm/send",
        #         headers={
        #             "Authorization": f"key={self.fcm_server_key}",
        #             "Content-Type": "application/json"
        #         },
        #         json={
        #             "to": device_token,
        #             "notification": {
        #                 "title": title,
        #                 "body": body,
        #                 "sound": "default"
        #             },
        #             "data": data or {}
        #         }
        #     )
        #     return response.json()

    async def send_match_challenge_notification(
        self,
        device_token: str,
        challenger_name: str,
        sport: str
    ):
        """Send match challenge notification."""
        await self.send_notification(
            device_token=device_token,
            title="New Match Challenge!",
            body=f"{challenger_name} has challenged you to a {sport} match",
            data={
                "type": "match_challenge",
                "challenger_name": challenger_name,
                "sport": sport
            }
        )

    async def send_friend_request_notification(
        self,
        device_token: str,
        requester_name: str
    ):
        """Send friend request notification."""
        await self.send_notification(
            device_token=device_token,
            title="New Friend Request",
            body=f"{requester_name} wants to connect with you",
            data={
                "type": "friend_request",
                "requester_name": requester_name
            }
        )

    async def send_match_result_notification(
        self,
        device_token: str,
        won: bool,
        opponent_name: str,
        rating_change: int
    ):
        """Send match result notification."""
        title = "Victory!" if won else "Match Complete"
        body = f"You {'defeated' if won else 'lost to'} {opponent_name}. Rating: {'+' if rating_change > 0 else ''}{rating_change}"

        await self.send_notification(
            device_token=device_token,
            title=title,
            body=body,
            data={
                "type": "match_result",
                "won": won,
                "opponent_name": opponent_name,
                "rating_change": rating_change
            }
        )

    async def send_badge_earned_notification(
        self,
        device_token: str,
        badge_name: str
    ):
        """Send badge unlocked notification."""
        await self.send_notification(
            device_token=device_token,
            title="Badge Unlocked! 🏆",
            body=f"You earned the '{badge_name}' badge!",
            data={
                "type": "badge_earned",
                "badge_name": badge_name
            }
        )

    async def send_leaderboard_update_notification(
        self,
        device_token: str,
        new_rank: int,
        sport: str
    ):
        """Send leaderboard rank change notification."""
        await self.send_notification(
            device_token=device_token,
            title="Leaderboard Update",
            body=f"You're now ranked #{new_rank} in {sport}!",
            data={
                "type": "leaderboard_update",
                "new_rank": new_rank,
                "sport": sport
            }
        )

    async def send_bulk_notifications(
        self,
        device_tokens: List[str],
        title: str,
        body: str,
        data: Optional[dict] = None
    ):
        """Send notification to multiple devices."""
        for token in device_tokens:
            await self.send_notification(token, title, body, data)


# Initialize service
push_service = PushNotificationService()


# Production APNs setup guide:
"""
1. Go to Apple Developer Portal (https://developer.apple.com)
2. Certificates, Identifiers & Profiles
3. Keys → Create a new key
4. Enable "Apple Push Notifications service (APNs)"
5. Download the .p8 key file
6. Note the Key ID and Team ID
7. Set environment variables:
   export APNS_KEY_ID="your_key_id"
   export APNS_TEAM_ID="your_team_id"
   export APNS_BUNDLE_ID="com.sportshub.app"
   export APNS_ENABLED="true"

8. Install dependencies:
   pip install aioapns

9. Update code to use production APNs client
"""

# Production FCM setup guide:
"""
1. Go to Firebase Console (https://console.firebase.google.com)
2. Create new project or select existing
3. Project Settings → Cloud Messaging
4. Copy Server key
5. Set environment variable:
   export FCM_SERVER_KEY="your_server_key"
   export FCM_ENABLED="true"

6. In iOS app:
   - Add GoogleService-Info.plist
   - Initialize Firebase in AppDelegate
   - Request notification permissions
   - Get FCM token

7. In Android app:
   - Add google-services.json
   - Initialize Firebase
   - Get FCM token
"""
