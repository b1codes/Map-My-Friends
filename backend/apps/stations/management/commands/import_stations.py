import json
from django.contrib.gis.geos import Point
from django.core.management.base import BaseCommand
from apps.stations.models import Station


class Command(BaseCommand):
    help = "Import train stations from OSM/Overpass JSON data."

    def add_arguments(self, parser):
        parser.add_argument(
            'file_path',
            type=str,
            help='Path to the JSON file containing station data.',
        )
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Delete all existing stations before importing.',
        )

    def handle(self, *args, **options):
        file_path = options['file_path']
        if options['clear']:
            deleted_count, _ = Station.objects.all().delete()
            self.stdout.write(f"Deleted {deleted_count} existing stations.")

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:
            self.stderr.write(f"Error reading file: {e}")
            return

        elements = data.get('elements', [])
        stations_to_create = []
        stations_to_update = []
        
        # Optimization: Fetch existing OSM IDs
        existing_osm_ids = set(
            Station.objects.values_list('osm_id', flat=True)
        )

        for el in elements:
            if el.get('type') != 'node':
                continue
            
            tags = el.get('tags', {})
            name = tags.get('name')
            if not name:
                continue

            osm_id = el.get('id')
            lat = el.get('lat')
            lon = el.get('lon')

            if osm_id is None or lat is None or lon is None:
                continue

            station_data = {
                'name': name,
                'osm_id': osm_id,
                'station_type': tags.get('railway', 'station'),
                'uic_ref': tags.get('uic_ref', ''),
                'city': tags.get('addr:city', ''),
                'country': tags.get('addr:country', ''),
                'location': Point(lon, lat, srid=4326),
            }

            if osm_id in existing_osm_ids:
                stations_to_update.append(station_data)
            else:
                stations_to_create.append(Station(**station_data))

        # Bulk create new stations
        if stations_to_create:
            Station.objects.bulk_create(stations_to_create, ignore_conflicts=True)
            self.stdout.write(f"Created {len(stations_to_create)} new stations.")

        # Update existing stations
        updated_count = 0
        for data in stations_to_update:
            oid = data.pop('osm_id')
            Station.objects.filter(osm_id=oid).update(**data)
            updated_count += 1

        if updated_count:
            self.stdout.write(f"Updated {updated_count} existing stations.")

        total = Station.objects.count()
        self.stdout.write(
            self.style.SUCCESS(f"Done! Total stations in database: {total}")
        )
