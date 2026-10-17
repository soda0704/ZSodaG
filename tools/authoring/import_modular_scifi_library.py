"""Import every unique model without replacing existing assets or level scenes."""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import argparse, hashlib, json, re

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/models/modular_scifi_megakit'


def import_library(archive: Path) -> None:
    seed = (ASSETS/'models/walls/WallAstra_Straight.gltf.import').read_text(encoding='utf-8')
    records = []
    added = 0
    with ZipFile(archive) as bundle:
        names = set(bundle.namelist())
        prefix = 'Modular SciFi MegaKit[Standard]/'
        for source in sorted(names):
            if source.startswith(prefix+'Textures/') and source.endswith('.png'):
                target = ASSETS/'textures'/PurePosixPath(source).name
                if not target.exists():
                    target.write_bytes(bundle.read(source))
        for source in sorted(names):
            if not source.startswith(prefix+'glTF/') or not source.endswith('.gltf'):
                continue
            relative = PurePosixPath(source).relative_to(prefix+'glTF')
            target = ASSETS/'models'/relative.parts[0].lower()/relative.name
            data = json.loads(bundle.read(source))
            for image in data.get('images', []):
                uri = image.get('uri', '')
                if uri and not uri.startswith('data:'):
                    name = PurePosixPath(uri.replace('\\', '/')).name
                    assert (ASSETS/'textures'/name).exists(), name
                    image['uri'] = '../../textures/'+name
            for buffer in data.get('buffers', []):
                if buffer['uri'].startswith('data:'):
                    continue
                binary = str(PurePosixPath(source).parent/buffer['uri'])
                if binary not in names:
                    binary = str(PurePosixPath(source).with_suffix('.bin'))
                    assert len(bundle.read(binary)) == buffer['byteLength']
                    buffer['uri'] = PurePosixPath(binary).name
                target.parent.mkdir(parents=True, exist_ok=True)
                destination = target.parent/buffer['uri']
                if not destination.exists():
                    destination.write_bytes(bundle.read(binary))
            if not target.exists():
                target.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
                added += 1
            resource = 'res://'+target.relative_to(ROOT).as_posix()
            settings_path = target.with_suffix('.gltf.import')
            if not settings_path.exists():
                digest = hashlib.md5(resource.encode()).hexdigest()
                imported = f'res://.godot/imported/{target.name}-{digest}.scn'
                settings = re.sub(r'^uid=.*\n', '', seed, flags=re.M)
                settings = re.sub(r'^path=.*$', f'path="{imported}"', settings, flags=re.M)
                settings = re.sub(r'^source_file=.*$', f'source_file="{resource}"', settings, flags=re.M)
                settings = re.sub(r'^dest_files=.*$', f'dest_files=["{imported}"]', settings, flags=re.M)
                settings_path.write_text(settings, encoding='utf-8')
            category = {'Walls':'walls','Platforms':'floors','Columns':'columns','Props':'props','Decals':'decals','Aliens':'aliens'}[relative.parts[0]]
            if relative.stem.startswith('Door_'):
                category = 'doors'
            records.append({'name':relative.stem,'source':source,'path':target.relative_to(ROOT).as_posix(),'category':category,'animated':bool(data.get('skins') or data.get('animations'))})
        extra = prefix+'OBJ/Props/Prop_Fan_Small_Propeller.obj'
        target = ASSETS/'models/props/Prop_Fan_Small_Propeller.obj'
        if not target.exists():
            target.write_bytes(bundle.read(extra))
            added += 1
        mtl = bundle.read(str(PurePosixPath(extra).with_suffix('.mtl'))).decode('utf-8')
        lines = []
        for line in mtl.splitlines():
            if line.startswith(('map_', 'bump ')):
                key, uri = line.split(maxsplit=1)
                name = PurePosixPath(uri.replace('\\','/')).name
                assert (ASSETS/'textures'/name).exists(), name
                line = key+' ../../textures/'+name
            lines.append(line)
        if not target.with_suffix('.mtl').exists():
            target.with_suffix('.mtl').write_text('\n'.join(lines)+'\n', encoding='utf-8')
        records.append({'name':target.stem,'source':extra,'path':target.relative_to(ROOT).as_posix(),'category':'props','animated':False})
    order = {c:i for i,c in enumerate(['walls','doors','floors','columns','props','decals','aliens'])}
    records.sort(key=lambda item:(order[item['category']],item['name']))
    assert len(records) == 191 and len({r['name'] for r in records}) == 191
    manifest = {'author':'Quaternius','license':'CC0-1.0','source_archive':archive.name,'models':records}
    (ASSETS/'library.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    print(f'Library: 191 models; added {added} sources; existing sources preserved.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    import_library(parser.parse_args().archive)
