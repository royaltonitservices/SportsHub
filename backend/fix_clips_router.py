#!/usr/bin/env python3
"""
Script to fix clips router to join author relationship
"""

with open('routers/clips.py', 'r') as f:
    content = f.read()

# Fix create_clip to load author
content = content.replace(
    '''    db.add(clip)
    db.commit()
    db.refresh(clip)

    return clip


@router.get("/feed"''',
    '''    db.add(clip)
    db.commit()
    db.refresh(clip)

    # Load author relationship for response
    clip.author = current_user

    return clip


@router.get("/feed"'''
)

# Fix get_clips_feed to join author
content = content.replace(
    '''    query = db.query(models.Clip)

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    return clips''',
    '''    query = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    )

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    return clips'''
)

# Fix get_clip to join author
content = content.replace(
    '''    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    # Increment view count
    clip.views_count += 1
    db.commit()

    return clip


@router.get("/user/{user_id}"''',
    '''    clip = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    ).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    # Increment view count
    clip.views_count += 1
    db.commit()

    return clip


@router.get("/user/{user_id}"'''
)

# Fix get_user_clips to join author
content = content.replace(
    '''    clips = db.query(models.Clip).filter(
        models.Clip.author_id == user_id
    ).order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    return clips


@router.get("/trending"''',
    '''    clips = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    ).filter(
        models.Clip.author_id == user_id
    ).order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    return clips


@router.get("/trending"'''
)

# Fix get_trending_clips to join author
content = content.replace(
    '''    query = db.query(models.Clip)

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(
        (models.Clip.views_count + models.Clip.likes_count * 5).desc()
    ).limit(limit).all()

    return clips


@router.post("/{clip_id}/like")''',
    '''    query = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    )

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(
        (models.Clip.views_count + models.Clip.likes_count * 5).desc()
    ).limit(limit).all()

    return clips


@router.post("/{clip_id}/like")'''
)

# Fix upload_clip to load author
content = content.replace(
    '''        db.add(clip)
        db.commit()
        db.refresh(clip)

        return clip

    except Exception as e:''',
    '''        db.add(clip)
        db.commit()
        db.refresh(clip)

        # Load author relationship for response
        clip.author = current_user

        return clip

    except Exception as e:'''
)

with open('routers/clips.py', 'w') as f:
    f.write(content)

print("Fixed clips.py")
