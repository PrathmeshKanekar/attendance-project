import uuid
from django.db import models
from django.conf import settings

class FaceDescriptor(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.OneToOneField('students.StudentProfile', on_delete=models.CASCADE, related_name='face_descriptor')
    embedding = models.JSONField()    # 128-float list from DeepFace/FaceNet
    model_used = models.CharField(max_length=50, default='DeepFace')
    registered_at = models.DateTimeField(auto_now_add=True)
    registered_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='registered_face_descriptors')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'face_recognition_descriptor'

    def __str__(self):
        return f"Face for {self.student}"

class FaceRegistrationImage(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.ForeignKey('students.StudentProfile', on_delete=models.CASCADE, related_name='face_images')
    image_path = models.CharField(max_length=500)
    angle = models.CharField(max_length=50, default='front')  # front / left / right
    uploaded_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'face_registration_image'

    def __str__(self):
        return f"Image ({self.angle}) for {self.student}"
