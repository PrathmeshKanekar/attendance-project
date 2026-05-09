from rest_framework import serializers
from .models import Notification, NoticeBoard

class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = '__all__'
        read_only_fields = ['is_read', 'read_at', 'created_at']

class NoticeBoardSerializer(serializers.ModelSerializer):
    created_by_name = serializers.ReadOnlyField(source='created_by.get_full_name')
    
    class Meta:
        model = NoticeBoard
        fields = '__all__'
        read_only_fields = ['created_by', 'created_at']
