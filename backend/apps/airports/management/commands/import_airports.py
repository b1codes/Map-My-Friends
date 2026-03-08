import csv
import io
import urllib.request

from django.contrib.gis.geos import Point
from django.core.management.base import BaseCommand

from apps.airports.models import Airport

OURAIRPORTS_CSV_URL = (
    "https://raw.githubusercontent.com/davidmegginson/ourairports-data/main/airports.csv"
)

ALLOWED_TYPES = {'large_airport', 'medium_airport'}


class Command(BaseCommand):
    help = "Import commercial airports from OurAirports CSV data."

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Delete all existing airports before importing.',
        )

    def handle(self, *args, **options):
        if options['clear']:
            deleted_count, _ = Airport.objects.all().delete()
            self.stdout.write(f"Deleted {deleted_count} existing airports.")

        self.stdout.write("Downloading airport data from OurAirports...")
        response = urllib.request.urlopen(OURAIRPORTS_CSV_URL)
        data = response.read().decode('utf-8')

        reader = csv.DictReader(io.StringIO(data))

        airports_to_create = []
        airports_to_update = []
        existing_iata_codes = set(
            Airport.objects.values_list('iata_code', flat=True)
        )
        seen_iata_codes = set()

        for row in reader:
            airport_type = row.get('type', '')
            iata_code = row.get('iata_code', '').strip()

            # Skip non-commercial airports and those without IATA codes
            if airport_type not in ALLOWED_TYPES:
                continue
            if not iata_code:
                continue
            # Skip duplicates within the CSV
            if iata_code in seen_iata_codes:
                continue
            seen_iata_codes.add(iata_code)

            try:
                lat = float(row['latitude_deg'])
                lon = float(row['longitude_deg'])
            except (ValueError, KeyError):
                continue

            airport_data = {
                'name': row.get('name', ''),
                'iata_code': iata_code,
                'icao_code': row.get('ident', '')[:4] if row.get('ident') else None,
                'airport_type': airport_type,
                'city': row.get('municipality', ''),
                'country': row.get('iso_country', ''),
                'continent': row.get('continent', ''),
                'location': Point(lon, lat, srid=4326),
            }

            if iata_code in existing_iata_codes:
                airports_to_update.append(airport_data)
            else:
                airports_to_create.append(Airport(**airport_data))

        # Bulk create new airports
        if airports_to_create:
            Airport.objects.bulk_create(airports_to_create, ignore_conflicts=True)
            self.stdout.write(f"Created {len(airports_to_create)} new airports.")

        # Update existing airports
        updated_count = 0
        for data in airports_to_update:
            iata = data.pop('iata_code')
            Airport.objects.filter(iata_code=iata).update(**data)
            updated_count += 1

        if updated_count:
            self.stdout.write(f"Updated {updated_count} existing airports.")

        total = Airport.objects.count()
        self.stdout.write(
            self.style.SUCCESS(f"Done! Total airports in database: {total}")
        )
