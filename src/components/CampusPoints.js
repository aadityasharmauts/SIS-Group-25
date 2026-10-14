// Coordinates are image pixels in [mapY, mapX] order.
// The map image is 1824 x 1824, so valid values are 0-1824.
// mapY = top-to-bottom, mapX = left-to-right.

export const CAMPUS_POINTS = [
    {
      id: 'building-01',
      code: '01',
      name: 'UTS Tower',
      description: 'Main administrative tower.',
      coords: [1010, 1010],
    },
    {
      id: 'building-02',
      code: '02',
      name: 'Building 02',
      description: 'Faculty of Arts and Social Sciences.',
      coords: [1115, 990],
    },
    {
      id: 'building-10',
      code: '10',
      name: 'Building 10',
      description: 'Faculty of Science.',
      coords: [910, 818],
    },
    {
      id: 'building-11',
      code: '11',
      name: 'UTS Library',
      description: 'Library and study spaces.',
      coords: [1080, 818],
    },
    {
      id: 'alumni-green',
      code: 'AG',
      name: 'Alumni Green',
      description: 'Open lawn between buildings.',
      coords: [970, 986],
    },
  ];
  