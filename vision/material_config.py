"""Opt-in material HSV profile. Never rewrites legacy vision/config.json."""
from dataclasses import asdict, dataclass, field
import json
from pathlib import Path
from .config import ColorConfig, number, validate_color

MATERIALS={1:'GREEN_SOLID',2:'BLUE_BOUNCE',3:'ORANGE_ONE_WAY'}
DEFAULT_PATH=Path(__file__).with_name('materials_config.json')


@dataclass
class MaterialConfig:
    colors: list[ColorConfig] = field(default_factory=lambda:[
        ColorConfig(1,'verde',[35,90,55],[85,255,255],min_area=12),
        ColorConfig(2,'azul',[95,100,55],[135,255,255],min_area=12),
        ColorConfig(3,'naranja',[5,120,65],[25,255,255],min_area=12)])
    opening_kernel: int = 0
    confirmation_frames: int = 3
    max_regions: int = 128
    max_parts: int = 512

    def validate(self):
        if sorted(c.id for c in self.colors)!=[1,2,3]:raise ValueError('material_color_ids')
        for c in self.colors:validate_color(c,3)
        if type(self.opening_kernel) is not int or self.opening_kernel not in (0,3,5):raise ValueError('opening_kernel')
        number(self.confirmation_frames,1,20,True)
        number(self.max_regions,1,128,True);number(self.max_parts,1,512,True)
        return self


def load_materials(path=DEFAULT_PATH):
    path=Path(path)
    if path.stat().st_size>1048576:raise ValueError('material_profile_size')
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    expected={'material_config_version','colors','opening_kernel','confirmation_frames','max_regions','max_parts'}
    if not isinstance(data,dict) or set(data)!=expected or type(data.get('material_config_version')) is not int or data.pop('material_config_version')!=1:raise ValueError('material_config_version_or_structure')
    try:
        data['colors']=[ColorConfig(**c) for c in data['colors']]
        return MaterialConfig(**data).validate()
    except (TypeError,KeyError,AttributeError) as e:
        raise ValueError('invalid_material_profile: '+str(e)) from e


def save_materials(config,path):
    config.validate();path=Path(path)
    if path.resolve()==Path(__file__).with_name('config.json').resolve():raise ValueError('legacy_config_is_protected')
    data={'material_config_version':1,**asdict(config)}
    tmp=path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n',encoding='utf-8');tmp.replace(path)
