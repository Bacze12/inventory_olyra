import React from 'react';
import { AbsoluteFill, staticFile, useVideoConfig } from 'remotion';
import { brandColor, brandColorDark, screens } from './screens';

const FRAME_W = 128;
const FRAME_H = 276;
const SCREEN_W = FRAME_W - 10;
const SCREEN_H = (SCREEN_W / 1080) * 2400;
const PUNCH = 6;

const phoneStyle = (top: number, left: number, rotate: number): React.CSSProperties => ({
  position: 'absolute',
  top,
  left,
  width: FRAME_W,
  height: FRAME_H,
  borderRadius: 15,
  background: '#0B0D12',
  boxShadow: '0 24px 40px rgba(0,0,0,0.45)',
  overflow: 'hidden',
  transform: `rotate(${rotate}deg)`,
});

export const PlayBanner: React.FC = () => {
  const { width, height } = useVideoConfig();
  const yCenter = 124;

  const phones = [
    { screen: screens[0], top: yCenter - 16, rotate: -9 },
    { screen: screens[1], top: yCenter, rotate: 0 },
    { screen: screens[2], top: yCenter - 16, rotate: 9 },
  ];

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(120deg, ${brandColorDark} 0%, #0A5F43 55%, #0E8B5C 100%)`,
        fontFamily: '"Segoe UI", system-ui, Arial, sans-serif',
        overflow: 'hidden',
      }}
    >
      <AbsoluteFill
        style={{
          background:
            'radial-gradient(900px 500px at 18% -10%, rgba(255,255,255,0.18), rgba(255,255,255,0) 55%)',
        }}
      />

      {/* Texto */}
      <div
        style={{
          position: 'absolute',
          left: 48,
          top: 0,
          height,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'flex-start',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 16 }}>
          <div
            style={{
              width: 62,
              height: 62,
              borderRadius: 20,
              background: '#FFFFFF',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 5,
            }}
          >
            <div style={{ width: 4, height: 26, background: brandColor, borderRadius: 3 }} />
            <div style={{ width: 10, height: 36, background: brandColor, borderRadius: 3 }} />
            <div style={{ width: 4, height: 22, background: brandColor, borderRadius: 3 }} />
            <div style={{ width: 7, height: 31, background: brandColor, borderRadius: 3 }} />
          </div>
          <div style={{ color: '#FFFFFF', fontSize: 52, fontWeight: 800, letterSpacing: -1 }}>
            BodegaFlow
          </div>
        </div>

        <div
          style={{
            color: 'rgba(255,255,255,0.85)',
            fontSize: 25,
            fontWeight: 500,
            marginTop: 14,
          }}
        >
          Inventario al instante, sin conexión.
        </div>

        <div
          style={{
            marginTop: 20,
            padding: '9px 18px',
            borderRadius: 999,
            background: 'rgba(255,255,255,0.14)',
            border: '1px solid rgba(255,255,255,0.35)',
            color: '#FFFFFF',
            fontSize: 19,
            fontWeight: 600,
            letterSpacing: 0.3,
          }}
        >
          Disponible en Google Play
        </div>
      </div>

      {/* Brillo detrás de los teléfonos */}
      <div
        style={{
          position: 'absolute',
          right: 40,
          top: 60,
          width: 470,
          height: 380,
          borderRadius: 200,
          background: 'radial-gradient(closest-side, rgba(255,255,255,0.12), rgba(255,255,255,0))',
        }}
      />

      {/* Teléfonos */}
      {phones.map((p, i) => (
        <div key={i} style={phoneStyle(p.top, width - 460 + i * 150, p.rotate)}>
          <div
            style={{
              position: 'absolute',
              top: 6,
              left: 5,
              width: SCREEN_W,
              height: SCREEN_H,
              borderRadius: 11,
              overflow: 'hidden',
              background: '#000',
            }}
          >
            <img
              src={staticFile(p.screen.image)}
              width={SCREEN_W}
              height={SCREEN_H}
              style={{ objectFit: 'cover', display: 'block' }}
            />
            <div
              style={{
                position: 'absolute',
                top: 7,
                left: SCREEN_W / 2 - PUNCH / 2,
                width: PUNCH,
                height: PUNCH,
                borderRadius: PUNCH / 2,
                background: '#0B0D12',
                border: '1px solid rgba(255,255,255,0.35)',
              }}
            />
          </div>
        </div>
      ))}
    </AbsoluteFill>
  );
};