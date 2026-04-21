# Generated migration for TripStop model changes

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('trips', '0001_initial'),
        ('people', '0003_person_pin_color_person_pin_emoji_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='tripstop',
            name='person',
            field=models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, to='people.person'),
        ),
        migrations.AlterModelOptions(
            name='tripstop',
            options={'ordering': ['sequence_order'], 'unique_together': {('trip', 'sequence_order')}},
        ),
    ]
