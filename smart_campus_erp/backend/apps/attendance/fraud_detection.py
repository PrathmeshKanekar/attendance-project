from .models import AttendanceLog
from apps.accounts.models import DeviceRegistry
from apps.virtual_rooms.geo_utils import check_inside_room, detect_gps_spoofing
from django.utils import timezone

class FraudDetector:
    @staticmethod
    def check_duplicate_submission(session_id, student_id):
        return AttendanceLog.objects.filter(session_id=session_id, student_id=student_id).exists()

    def check_gps_validity(self, lat, lng, altitude, room):
        if room is None:
            return {'inside': False, 'reason': 'No virtual room configured for this session'}
        return check_inside_room(lat, lng, altitude, room)

    @staticmethod
    def check_device_binding(device_id, student_user):
        # A student must use their registered device
        return DeviceRegistry.objects.filter(user=student_user, device_id=device_id, is_active=True).exists()

    @staticmethod
    def check_gps_spoofing(lat, lng, student_id):
        # Get student's last 3 attendance locations across all sessions
        last_logs = AttendanceLog.objects.filter(student_id=student_id).order_by('-marked_at')[:1]
        
        if not last_logs.exists():
            return {'spoofed': False, 'reason': 'first attendance record'}
            
        last_log = last_logs[0]
        time_diff = (timezone.now() - last_log.marked_at).total_seconds()
        
        result = detect_gps_spoofing(
            lat, lng, 
            float(last_log.marked_lat) if last_log.marked_lat else None, 
            float(last_log.marked_lng) if last_log.marked_lng else None, 
            time_diff
        )
        return result

    def run_all_checks(self, session, student_user, lat, lng, altitude, device_id):
        results = {
            'duplicate': self.check_duplicate_submission(session.id, student_user.id),
            'gps': self.check_gps_validity(lat, lng, altitude, session.virtual_room),
            'device': self.check_device_binding(device_id, student_user),
            'spoofing': self.check_gps_spoofing(lat, lng, student_user.id)
        }
        
        # Consolidation
        all_passed = (
            not results['duplicate'] and 
            results['gps'].get('inside', True) and 
            results['device'] and 
            not results['spoofing'].get('spoofed', False)
        )
        
        return {
            'passed': all_passed,
            'details': results
        }
