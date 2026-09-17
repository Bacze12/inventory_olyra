export type ScreenId = 'home' | 'productos' | 'escaner';

export type CanvasSize = 'phone' | 'tall';

export interface Screen {
  id: ScreenId;
  image: string;
  title: string;
  tagline: string;
}

export const screens: Screen[] = [
  {
    id: 'home',
    image: 'home.png',
    title: 'Inventario al instante',
    tagline: 'Escanea, cuenta y mantén tu stock sin conexión.',
  },
  {
    id: 'productos',
    image: 'productos.png',
    title: 'Stock siempre al día',
    tagline: 'Códigos de barras y alertas de stock mínimo.',
  },
  {
    id: 'escaner',
    image: 'escaner.png',
    title: 'Escanea sin conexión',
    tagline: 'Entradas y salidas con la cámara, al instante.',
  },
];

export const canvasSizes: { id: CanvasSize; width: number; height: number }[] = [
  { id: 'phone', width: 1080, height: 1920 },
  { id: 'tall', width: 1080, height: 2400 },
];

export const brandColor = '#006B4F';
export const brandColorDark = '#004C39';