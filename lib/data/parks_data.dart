// lib/data/parks_data.dart

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 公園資料結構
class Park {
  final String name;
  final LatLng location;
  const Park(this.name, this.location);
}

/// 台北市公園列表
const List<Park> taipeiParks = [
  Park('新生公園', LatLng(25.0697, 121.5292)),
  Park('大安森林公園', LatLng(25.0323, 121.5368)),
  Park('青年公園', LatLng(25.0245, 121.5037)),
  Park('榮星花園公園', LatLng(25.0637, 121.5408)),
  Park('南港公園', LatLng(25.0456, 121.6152)),
  Park('美堤河濱公園', LatLng(25.0740, 121.5583)),
  Park('至善公園', LatLng(25.1054, 121.5517)),
  Park('象山公園', LatLng(25.0319, 121.5702)),
  Park('士林官邸公園', LatLng(25.0954, 121.5262)),
  Park('北投公園', LatLng(25.1364, 121.5068)),
  Park('國父紀念館', LatLng(25.0407, 121.5600)),
  Park('中正紀念堂', LatLng(25.0350, 121.5218)),
  Park('大湖公園', LatLng(25.0830, 121.6094)),
  Park('碧湖公園', LatLng(25.0858, 121.5898)),
  Park('天母運動公園', LatLng(25.1165, 121.5312)),
];

/// 新北市公園列表
const List<Park> newTaipeiParks = [
  Park('板橋音樂公園', LatLng(25.0189, 121.4623)),
  Park('新莊運動公園', LatLng(25.0401, 121.4518)),
  Park('碧潭風景區', LatLng(24.9567, 121.5367)),
  Park('陽光運動公園', LatLng(24.9740, 121.5222)),
  Park('永和仁愛公園', LatLng(25.0063, 121.5134)),
  Park('中和公園（八二三紀念公園）', LatLng(25.0001, 121.4981)),
  Park('三重幸福水漾公園', LatLng(25.0593, 121.4883)),
  Park('淡水金色水岸', LatLng(25.1688, 121.4423)),
  Park('八里左岸公園', LatLng(25.1585, 121.4332)),
  Park('三峽客家文化園區', LatLng(24.9221, 121.3789)),
];
