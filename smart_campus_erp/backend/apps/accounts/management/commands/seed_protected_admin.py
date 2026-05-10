from django.core.management.base import BaseCommand
from apps.accounts.models import User
from django.db import transaction

class Command(BaseCommand):
    help = 'Seed the permanent protected Super Admin account'

    def handle(self, *args, **options):
        email = 'superadmin@app.com'
        password = 'admin@123'

        with transaction.atomic():
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    'first_name': 'Permanent',
                    'last_name': 'SuperAdmin',
                    'role': 'super_admin',
                    'is_staff': True,
                    'is_superuser': True,
                    'is_active': True,
                    'is_approved': True,
                }
            )

            if created:
                user.set_password(password)
                user.save()
                self.stdout.write(self.style.SUCCESS(f'Successfully created permanent super admin: {email}'))
            else:
                # Ensure it remains a super admin with these credentials
                user.role = 'super_admin'
                user.is_active = True
                user.is_approved = True
                user.is_superuser = True
                user.set_password(password)
                user.save()
                self.stdout.write(self.style.SUCCESS(f'Verified/Updated permanent super admin: {email}'))
