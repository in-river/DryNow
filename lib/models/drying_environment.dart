enum DryingPlace {
  openBalcony('開放的なベランダ', WindExposure.good),
  enclosedBalcony('壁に囲まれたベランダ', WindExposure.normal),
  garden('庭・屋外', WindExposure.good),
  underEaves('軒下', WindExposure.poor);

  const DryingPlace(this.label, this.suggestedWind);
  final String label;
  final WindExposure suggestedWind;
}

enum WindExposure {
  good('良い'),
  normal('普通'),
  poor('悪い');

  const WindExposure(this.label);
  final String label;
}

enum SunExposurePattern {
  allDay('一日中日が当たる'),
  morningOnly('午前のみ日が当たる'),
  afternoonOnly('午後のみ日が当たる'),
  shaded('一日中ほぼ日が当たらない');

  const SunExposurePattern(this.label);
  final String label;
}

class DryingEnvironment {
  const DryingEnvironment({
    required this.roofProtection,
    required this.dryingPlace,
    required this.windExposure,
    required this.sunExposurePattern,
  });

  final bool roofProtection;
  final DryingPlace dryingPlace;
  final WindExposure windExposure;
  final SunExposurePattern sunExposurePattern;

  Map<String, Object> toJson() => {
    'version': 1,
    'roofProtection': roofProtection,
    'dryingPlace': dryingPlace.name,
    'windExposure': windExposure.name,
    'sunExposurePattern': sunExposurePattern.name,
  };

  static DryingEnvironment? fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != 1 ||
        json['roofProtection'] is! bool) {
      return null;
    }
    T? named<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final place = named(DryingPlace.values, json['dryingPlace']);
    final wind = named(WindExposure.values, json['windExposure']);
    final sun = named(SunExposurePattern.values, json['sunExposurePattern']);
    if (place == null || wind == null || sun == null) return null;
    return DryingEnvironment(
      roofProtection: json['roofProtection'] as bool,
      dryingPlace: place,
      windExposure: wind,
      sunExposurePattern: sun,
    );
  }
}
