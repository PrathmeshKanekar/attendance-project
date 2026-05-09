import firebase_admin
from firebase_admin import credentials, messaging
from django.conf import settings
from apps.accounts.models import DeviceRegistry
import logging

logger = logging.getLogger(__name__)

class FCMService:
    def __init__(self):
        try:
            # Initialize Firebase app if not already initialized
            if not firebase_admin._apps:
                cred_path = getattr(settings, 'FIREBASE_CREDENTIALS_PATH', None)
                if cred_path:
                    cred = credentials.Certificate(cred_path)
                    firebase_admin.initialize_app(cred)
                else:
                    logger.warning("FIREBASE_CREDENTIALS_PATH not set")
        except Exception as e:
            logger.error(f"FCM Initialization error: {e}")

    def send_to_user(self, user_id, title, body, data={}):
        """
        Sends push notification to all active devices of a user.
        """
        tokens = DeviceRegistry.objects.filter(
            user_id=user_id, 
            is_active=True
        ).values_list('fcm_token', flat=True)
        
        if not tokens:
            return 0
            
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=data,
            tokens=list(tokens)
        )
        
        response = messaging.send_multicast(message)
        
        if response.failure_count > 0:
            # Logic to deactivate failed tokens
            for i, res in enumerate(response.responses):
                if not res.success:
                    DeviceRegistry.objects.filter(fcm_token=tokens[i]).update(is_active=False)
                    
        return response.success_count

    def send_to_college(self, college_id, title, body, roles=None):
        """
        Bulk send to all users in a college, optionally filtered by roles.
        """
        from apps.accounts.models import User
        users = User.objects.filter(college_id=college_id, is_active=True)
        if roles:
            users = users.filter(role__in=roles)
            
        user_ids = users.values_list('id', flat=True)
        tokens = DeviceRegistry.objects.filter(
            user_id__in=user_ids, 
            is_active=True
        ).values_list('fcm_token', flat=True)
        
        # FCM supports up to 500 tokens per multicast
        success_total = 0
        token_list = list(tokens)
        for i in range(0, len(token_list), 500):
            batch = token_list[i:i+500]
            message = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=body),
                tokens=batch
            )
            response = messaging.send_multicast(message)
            success_total += response.success_count
            
        return success_total
