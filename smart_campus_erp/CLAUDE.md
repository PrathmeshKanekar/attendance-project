# Smart Campus ERP - Project Context

## Overview
This is an EXISTING production Smart Campus Attendance ERP system with three main components:
- **Backend**: Django REST Framework + GeoDjango (PostgreSQL/PostGIS) at `backend/`
- **Frontend**: Flutter mobile app at `frontend/mobile_app/`
- **AR Module**: Unity project for AR room capture at `unity_project/`

## Architecture

### Backend (`backend/`)
- Django apps under `apps/` (virtual_rooms, attendance, users, colleges, divisions, approvals)
- REST API with JWT authentication
- Role-based access: Super Admin, College Admin, Principal, HOD, Teacher, Student, Non-Teaching Staff
- GeoDjango spatial features for virtual room boundaries
- Runs on `python manage.py runserver 0.0.0.0:8000`

### Frontend (`frontend/mobile_app/`)
- Flutter with Riverpod state management
- go_router navigation
- flutter_unity_widget for AR integration
- Feature-based folder structure under `lib/features/`
- Dio HTTP client for API communication
- Role-based dashboards and navigation

### Unity AR (`unity_project/`)
- AR Foundation (ARCore + ARKit)
- Spatial mapping and SLAM tracking
- C# scripts under `Assets/Scripts/`
- Flutter ↔ Unity bridge via flutter_unity_widget

## Key Conventions
- Backend serializers in `apps/<app>/serializers.py`
- Backend views in `apps/<app>/views.py`
- Backend models in `apps/<app>/models.py`
- Frontend screens in `lib/features/<feature>/presentation/screens/`
- Frontend widgets in `lib/features/<feature>/presentation/widgets/`
- State management via Riverpod providers in `lib/features/<feature>/providers/`

---

## GLOBAL PROJECT RULES (ALL TEAMMATES MUST FOLLOW)

### DO NOT MODIFY
- Authentication system
- Login flow
- Approval structure
- Academic modules
- Unrelated APIs
- Unrelated UI
- Role permissions
- Attendance business rules
- JWT system

### ONLY IMPROVE
- Virtual room system
- AR room capture
- Geo location flow (frontend device capture only)
- Room preview
- Room rendering
- Room storage
- Attendance room validation
- Frontend performance
- Backend performance
- AR performance

---

## CRITICAL: GEO LOCATION RULE

**GPS/location MUST be captured ONLY on the frontend device.**

- Backend server always returns server location, NOT user location
- Frontend captures GPS coordinates from the device
- Frontend captures AR coordinates from Unity
- Frontend captures spatial data
- Backend ONLY stores the final validated room data

### GPS is ONLY for:
- Classroom center point
- Attendance geo-fence fallback

### GPS is NEVER used for:
- Room geometry
- Room walls
- Room dimensions
- Room polygon generation

### Room geometry MUST use:
- Unity AR world-space X/Y/Z coordinates

---

## COORDINATE SYSTEM

```
X = left/right
Y = height
Z = forward/backward
```

- First corner: `(0, 0, 0)` (origin)
- All other corners: relative to origin

---

## AR ROOM CREATION FLOW

1. Teacher opens Create Virtual Room
2. Unity AR initializes
3. Floor plane detected
4. Teacher physically walks to room corners
5. User taps "Capture Corner"
6. Unity captures X/Y/Z coordinates
7. Flutter displays realtime room preview
8. Room mesh generated
9. GPS captured from frontend device
10. Backend stores final room data

---

## Agent Team Guidelines

### "frontend" teammate — Senior Flutter Architect + UI/UX Engineer
**Owns**: `frontend/mobile_app/` — Flutter/Dart files ONLY

**Responsibilities**:
- Flutter mobile app, Riverpod state management, go_router navigation
- flutter_unity_widget integration, AR room UI, attendance UI
- Realtime room preview, GPS capture from DEVICE ONLY
- Performance optimization, form validation, responsive layouts
- Smooth animations, API integration, error handling

**MUST preserve**: existing light theme, app architecture, color system, auth flow, role system

**MUST NOT**: redesign unrelated pages, modify backend logic, modify JWT, modify approvals, modify unrelated modules

### "backend" teammate — Senior Django Backend Architect + PostgreSQL/PostGIS Engineer
**Owns**: `backend/` — Python/Django files ONLY

**Responsibilities**:
- Django REST Framework APIs, PostgreSQL/PostGIS
- Serializers, views, models, geo utilities
- Room persistence, spatial room storage, attendance APIs
- Query optimization, caching, response optimization
- Migrations, validation handling, API stability

**MUST preserve**: existing APIs, authentication, approval workflows, attendance rules, architecture

**MUST NOT**: capture GPS from server, use server-side geo capture, redesign unrelated modules, modify login logic, break backward compatibility

### "unity" teammate — Senior Unity AR Engineer + Spatial Computing Engineer
**Owns**: `unity_project/` — C#/Unity files ONLY

**Responsibilities**:
- Unity AR Foundation, ARCore/ARKit integration
- SLAM tracking, spatial mapping, plane detection
- X/Y/Z coordinate system, room mesh generation, AR anchors
- Realtime room rendering (walls, floor, ceiling)
- Room polygon generation, Flutter ↔ Unity bridge
- AR performance optimization

**MUST**: use AR Foundation, proper spatial coordinates, generate realtime room preview, create stable room mesh, optimize FPS, prevent drift

**MUST NOT**: redesign Flutter UI, modify backend APIs, use fake coordinate generation, generate invalid geometry

---

## Quality Requirements
- Smooth 60 FPS UI
- Stable AR tracking
- Fast room capture
- Low API response time
- Realtime room preview
- Optimized database queries
- Proper validation
- Zero runtime crashes
- Clean architecture
- Scalable codebase

## Output Requirements
- Production-ready code only
- No pseudo code
- No placeholders
- No TODO comments
- No incomplete methods
