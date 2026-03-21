"""
Comment system endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from database import get_db
from dependencies import get_current_user
import models
import schemas

router = APIRouter(prefix="/comments", tags=["comments"])


@router.post("/create", response_model=schemas.CommentResponse)
async def create_comment(
    comment_data: schemas.CommentCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a comment on a post
    """
    # Verify post exists
    post = db.query(models.Post).filter(
        models.Post.id == comment_data.post_id
    ).first()

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    # If replying to a comment, verify it exists
    if comment_data.parent_comment_id:
        parent = db.query(models.Comment).filter(
            models.Comment.id == comment_data.parent_comment_id
        ).first()

        if not parent:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Parent comment not found"
            )

        # Verify parent belongs to the same post
        if parent.post_id != comment_data.post_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Parent comment belongs to different post"
            )

    # Create comment
    new_comment = models.Comment(
        post_id=comment_data.post_id,
        author_id=current_user.id,
        content=comment_data.content,
        parent_comment_id=comment_data.parent_comment_id
    )

    # Update post comment count
    post.comments_count += 1

    db.add(new_comment)
    db.commit()
    db.refresh(new_comment)

    return new_comment


@router.get("/post/{post_id}", response_model=List[schemas.CommentResponse])
async def get_post_comments(
    post_id: UUID,
    db: Session = Depends(get_db)
):
    """
    Get all comments for a post
    """
    comments = db.query(models.Comment).filter(
        models.Comment.post_id == post_id
    ).order_by(models.Comment.created_at.desc()).all()

    return comments


@router.delete("/{comment_id}")
async def delete_comment(
    comment_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete a comment (author or admin only)
    """
    comment = db.query(models.Comment).filter(
        models.Comment.id == comment_id
    ).first()

    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Comment not found"
        )

    # Check authorization
    if comment.author_id != current_user.id and current_user.role != models.UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to delete this comment"
        )

    # Update post comment count
    post = db.query(models.Post).filter(
        models.Post.id == comment.post_id
    ).first()

    if post:
        post.comments_count = max(0, post.comments_count - 1)

    db.delete(comment)
    db.commit()

    return {"message": "Comment deleted successfully"}


@router.post("/like/{comment_id}")
async def like_comment(
    comment_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Like a comment (placeholder - would need a likes table for full implementation)
    """
    comment = db.query(models.Comment).filter(
        models.Comment.id == comment_id
    ).first()

    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Comment not found"
        )

    comment.likes_count += 1
    db.commit()

    return {"message": "Comment liked", "likes_count": comment.likes_count}
