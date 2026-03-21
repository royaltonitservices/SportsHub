"""
Direct messaging endpoints (friends-only)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import List
from uuid import UUID
from datetime import datetime
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/messages", tags=["messages"])


def are_friends(user_a_id: UUID, user_b_id: UUID, db: Session) -> bool:
    """Check if two users are friends"""
    friendship = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == user_a_id,
                models.Friendship.user_b_id == user_b_id
            ),
            and_(
                models.Friendship.user_a_id == user_b_id,
                models.Friendship.user_b_id == user_a_id
            )
        ),
        models.Friendship.status == models.FriendshipStatus.ACCEPTED
    ).first()

    return friendship is not None


@router.post("/send", response_model=schemas.MessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    message_data: schemas.MessageCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Send a direct message to a friend"""

    # Can't message yourself
    if message_data.receiver_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send message to yourself"
        )

    # Check if receiver exists
    receiver = db.query(models.User).filter(models.User.id == message_data.receiver_id).first()
    if not receiver:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Verify friendship
    if not are_friends(current_user.id, message_data.receiver_id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Can only message friends"
        )

    # Create message
    message = models.Message(
        sender_id=current_user.id,
        receiver_id=message_data.receiver_id,
        content=message_data.content,
        safety_checked=False,  # Will be checked by AI moderation service
        moderation_status="pending"
    )

    db.add(message)
    db.commit()
    db.refresh(message)

    return message


@router.get("/conversation/{user_id}", response_model=List[schemas.MessageResponse])
async def get_conversation(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    limit: int = 50
):
    """Get message history with a specific user"""

    # Verify friendship
    if not are_friends(current_user.id, user_id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Can only view messages with friends"
        )

    # Get messages between the two users
    messages = db.query(models.Message).filter(
        or_(
            and_(
                models.Message.sender_id == current_user.id,
                models.Message.receiver_id == user_id,
                models.Message.deleted_by_sender == False
            ),
            and_(
                models.Message.sender_id == user_id,
                models.Message.receiver_id == current_user.id,
                models.Message.deleted_by_receiver == False
            )
        )
    ).order_by(models.Message.sent_at.desc()).limit(limit).all()

    # Mark messages as read
    for message in messages:
        if message.receiver_id == current_user.id and message.read_at is None:
            message.read_at = datetime.utcnow()

    db.commit()

    return messages[::-1]  # Reverse to show oldest first


@router.get("/conversations", response_model=List[dict])
async def get_all_conversations(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get list of all conversations with last message preview"""

    # Get all friends
    friendships = db.query(models.Friendship).filter(
        or_(
            models.Friendship.user_a_id == current_user.id,
            models.Friendship.user_b_id == current_user.id
        ),
        models.Friendship.status == models.FriendshipStatus.ACCEPTED
    ).all()

    conversations = []

    for friendship in friendships:
        # Determine friend's ID
        friend_id = friendship.user_b_id if friendship.user_a_id == current_user.id else friendship.user_a_id

        # Get last message
        last_message = db.query(models.Message).filter(
            or_(
                and_(
                    models.Message.sender_id == current_user.id,
                    models.Message.receiver_id == friend_id,
                    models.Message.deleted_by_sender == False
                ),
                and_(
                    models.Message.sender_id == friend_id,
                    models.Message.receiver_id == current_user.id,
                    models.Message.deleted_by_receiver == False
                )
            )
        ).order_by(models.Message.sent_at.desc()).first()

        # Get unread count
        unread_count = db.query(models.Message).filter(
            models.Message.sender_id == friend_id,
            models.Message.receiver_id == current_user.id,
            models.Message.read_at.is_(None),
            models.Message.deleted_by_receiver == False
        ).count()

        # Get friend details
        friend = db.query(models.User).filter(models.User.id == friend_id).first()

        if last_message:
            conversations.append({
                "friend_id": str(friend_id),
                "friend_username": friend.username,
                "friend_display_name": friend.display_name,
                "friend_avatar_seed": friend.avatar_seed,
                "last_message": last_message.content,
                "last_message_time": last_message.sent_at,
                "unread_count": unread_count
            })

    # Sort by last message time
    conversations.sort(key=lambda x: x["last_message_time"], reverse=True)

    return conversations


@router.delete("/{message_id}")
async def delete_message(
    message_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Delete a message (soft delete)"""

    message = db.query(models.Message).filter(models.Message.id == message_id).first()

    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found"
        )

    # Mark as deleted for the appropriate user
    if message.sender_id == current_user.id:
        message.deleted_by_sender = True
    elif message.receiver_id == current_user.id:
        message.deleted_by_receiver = True
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot delete this message"
        )

    db.commit()

    return {"message": "Message deleted"}


# Group Messaging Endpoints
@router.post("/groups/create", response_model=schemas.GroupChatResponse)
async def create_group_chat(
    group_data: schemas.GroupChatCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Create a new group chat"""
    import uuid as uuid_pkg
    import random
    import string

    # Generate avatar seed for consistent group avatars
    avatar_seed = ''.join(random.choices(string.ascii_letters + string.digits, k=10))

    group = models.GroupChat(
        name=group_data.name,
        description=group_data.description,
        creator_id=current_user.id,
        avatar_seed=avatar_seed
    )

    db.add(group)
    db.flush()  # Get group ID

    # Add creator as admin member
    creator_member = models.GroupChatMember(
        group_id=group.id,
        user_id=current_user.id,
        role="admin"
    )
    db.add(creator_member)

    # Add other members
    for member_id in group_data.member_ids:
        if member_id != str(current_user.id):  # Don't add creator twice
            member = models.GroupChatMember(
                group_id=group.id,
                user_id=uuid_pkg.UUID(member_id),
                role="member"
            )
            db.add(member)

    db.commit()
    db.refresh(group)

    # Calculate member count
    member_count = db.query(models.GroupChatMember).filter(
        models.GroupChatMember.group_id == group.id
    ).count()

    return schemas.GroupChatResponse(
        id=group.id,
        name=group.name,
        description=group.description,
        creator_id=group.creator_id,
        avatar_seed=group.avatar_seed,
        created_at=group.created_at,
        member_count=member_count,
        last_message=None,
        last_message_at=None,
        unread_count=0
    )


@router.get("/groups", response_model=List[schemas.GroupChatResponse])
async def get_user_groups(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all group chats the user is a member of"""
    # Get groups where user is a member
    memberships = db.query(models.GroupChatMember).filter(
        models.GroupChatMember.user_id == current_user.id
    ).all()

    group_responses = []
    for membership in memberships:
        group = db.query(models.GroupChat).filter(
            models.GroupChat.id == membership.group_id
        ).first()

        if not group:
            continue

        # Get member count
        member_count = db.query(models.GroupChatMember).filter(
            models.GroupChatMember.group_id == group.id
        ).count()

        # Get last message
        last_message = db.query(models.Message).filter(
            models.Message.group_id == group.id
        ).order_by(models.Message.sent_at.desc()).first()

        # Get unread count (messages after user's last_read_at)
        unread_count = 0
        if membership.last_read_at:
            unread_count = db.query(models.Message).filter(
                and_(
                    models.Message.group_id == group.id,
                    models.Message.sent_at > membership.last_read_at
                )
            ).count()
        else:
            # If never read, count all messages
            unread_count = db.query(models.Message).filter(
                models.Message.group_id == group.id
            ).count()

        group_responses.append(schemas.GroupChatResponse(
            id=group.id,
            name=group.name,
            description=group.description,
            creator_id=group.creator_id,
            avatar_seed=group.avatar_seed,
            created_at=group.created_at,
            member_count=member_count,
            last_message=last_message.content if last_message else None,
            last_message_at=last_message.sent_at if last_message else None,
            unread_count=unread_count
        ))

    return group_responses


@router.get("/groups/{group_id}/messages", response_model=List[schemas.GroupMessageResponse])
async def get_group_messages(
    group_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    limit: int = 50
):
    """Get messages from a group chat"""
    import uuid as uuid_pkg

    group_uuid = uuid_pkg.UUID(group_id)

    # Verify user is a member
    membership = db.query(models.GroupChatMember).filter(
        and_(
            models.GroupChatMember.group_id == group_uuid,
            models.GroupChatMember.user_id == current_user.id
        )
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a member of this group"
        )

    # Get messages
    messages = db.query(models.Message).filter(
        models.Message.group_id == group_uuid
    ).order_by(models.Message.sent_at.desc()).limit(limit).all()

    # Update last_read_at
    membership.last_read_at = datetime.utcnow()
    db.commit()

    # Format response
    responses = []
    for msg in reversed(messages):
        sender = db.query(models.User).filter(models.User.id == msg.sender_id).first()
        responses.append(schemas.GroupMessageResponse(
            id=msg.id,
            group_id=msg.group_id,
            sender_id=msg.sender_id,
            sender_name=sender.display_name or sender.username if sender else "Unknown",
            content=msg.content,
            sent_at=msg.sent_at
        ))

    return responses


@router.post("/groups/{group_id}/send", response_model=schemas.GroupMessageResponse)
async def send_group_message(
    group_id: str,
    message_data: schemas.GroupMessageCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Send a message to a group chat"""
    import uuid as uuid_pkg

    group_uuid = uuid_pkg.UUID(group_id)

    # Verify user is a member
    membership = db.query(models.GroupChatMember).filter(
        and_(
            models.GroupChatMember.group_id == group_uuid,
            models.GroupChatMember.user_id == current_user.id
        )
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a member of this group"
        )

    # Create message
    message = models.Message(
        sender_id=current_user.id,
        group_id=group_uuid,
        content=message_data.content,
        safety_checked=False,
        moderation_status="pending"
    )

    db.add(message)
    db.commit()
    db.refresh(message)

    return schemas.GroupMessageResponse(
        id=message.id,
        group_id=message.group_id,
        sender_id=message.sender_id,
        sender_name=current_user.display_name or current_user.username,
        content=message.content,
        sent_at=message.sent_at
    )


@router.post("/groups/{group_id}/members")
async def add_group_members(
    group_id: str,
    member_ids: List[str],
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Add members to a group chat (admin only)"""
    import uuid as uuid_pkg

    group_uuid = uuid_pkg.UUID(group_id)

    # Verify user is an admin
    membership = db.query(models.GroupChatMember).filter(
        and_(
            models.GroupChatMember.group_id == group_uuid,
            models.GroupChatMember.user_id == current_user.id
        )
    ).first()

    if not membership or membership.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins can add members"
        )

    # Add members
    added_members = []
    for member_id in member_ids:
        # Check if already a member
        existing = db.query(models.GroupChatMember).filter(
            and_(
                models.GroupChatMember.group_id == group_uuid,
                models.GroupChatMember.user_id == uuid_pkg.UUID(member_id)
            )
        ).first()

        if not existing:
            member = models.GroupChatMember(
                group_id=group_uuid,
                user_id=uuid_pkg.UUID(member_id),
                role="member"
            )
            db.add(member)
            added_members.append(member_id)

    db.commit()

    return {"added_members": added_members}


@router.delete("/groups/{group_id}/leave")
async def leave_group(
    group_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Leave a group chat"""
    import uuid as uuid_pkg

    group_uuid = uuid_pkg.UUID(group_id)

    # Find membership
    membership = db.query(models.GroupChatMember).filter(
        and_(
            models.GroupChatMember.group_id == group_uuid,
            models.GroupChatMember.user_id == current_user.id
        )
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not a member of this group"
        )

    db.delete(membership)
    db.commit()

    return {"message": "Left group successfully"}
