from twilio.rest import Client
from django.conf import settings
import logging

logger = logging.getLogger(__name__)

class SMSService:
    def __init__(self):
        self.account_sid = getattr(settings, 'TWILIO_ACCOUNT_SID', None)
        self.auth_token = getattr(settings, 'TWILIO_AUTH_TOKEN', None)
        self.from_number = getattr(settings, 'TWILIO_PHONE_NUMBER', None)
        
        if self.account_sid and self.auth_token:
            self.client = Client(self.account_sid, self.auth_token)
        else:
            self.client = None
            logger.warning("Twilio credentials not fully set")

    def send_sms(self, to, body):
        if not self.client:
            logger.error("Twilio client not initialized")
            return False
        try:
            message = self.client.messages.create(
                body=body,
                from_=self.from_number,
                to=to
            )
            return message.sid
        except Exception as e:
            logger.error(f"SMS Send error: {e}")
            return False

    def send_otp(self, mobile, otp_code):
        body = f"Your Smart Campus verification code is: {otp_code}. Valid for 10 minutes."
        return self.send_sms(mobile, body)

    def send_attendance_alert(self, parent_mobile, student_name, subject, date):
        body = f"Attendance Alert: {student_name} was marked ABSENT for {subject} on {date}."
        return self.send_sms(parent_mobile, body)
