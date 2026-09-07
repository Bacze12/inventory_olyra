import React from 'react';
import { AbsoluteFill } from 'remotion';
import { brandColor, brandColorDark } from './screens';

const CARD = 214;

const bar = (w: number, h: number, align: 'top' | 'bottom'): React.CSSProperties => ({
  width: w,
  height: h,
  background: brandColor,
  borderRadius: 10,
  position: 'absolute',
  bottom: align === 'bottom' ? (CARD - h) / 2 : undefined,
  top: align === 'top' ? (CARD - h) / 2 : undefined,
});

const corner = (t: number, l: number, style: React.CSSProperties): React.CSSProperties => ({
  position: 'absolute',
  top: t,
  left: l,
  width: 52,
  height: 52,
  borderStyle: 'solid',
  borderColor: 'rgba(255,255,255,0.75)',
  background: 'transparent',
  ...style,
});

export const Icon512: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `linear-gradient(135deg, ${brandColorDark} 0%, #0A5F43 50%, #0E8B5C 100%)`,
    }}
  >
    {/* Marco de escáner */}
    <div style={corner(26, 26, { borderWidth: '10px 0 0 10px', borderTopLeftRadius: 24 })} />
    <div style={corner(26, 512 - 26 - 52, { borderWidth: '10px 10px 0 0', borderTopRightRadius: 24 })} />
    <div style={corner(512 - 26 - 52, 26, { borderWidth: '0 0 10px 10px', borderBottomLeftRadius: 24 })} />
    <div
      style={corner(512 - 26 - 52, 512 - 26 - 52, {
        borderWidth: '0 10px 10px 0',
        borderBottomRightRadius: 24,
      })}
    />

    {/* Resplandor sutil */}
    <div
      style={{
        position: 'absolute',
        top: 90,
        left: '50%',
        transform: 'translateX(-50%)',
        width: 330,
        height: 330,
        borderRadius: 165,
        background: 'radial-gradient(closest-side, rgba(255,255,255,0.14), rgba(255,255,255,0))',
      }}
    />

    {/* Tarjeta / logo */}
    <div
      style={{
        position: 'absolute',
        left: (512 - CARD) / 2,
        top: (512 - CARD) / 2,
        width: CARD,
        height: CARD,
        borderRadius: 56,
        background: '#FFFFFF',
        boxShadow: '0 26px 44px rgba(0,0,0,0.32)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 14,
        position: 'relative',
      } as React.CSSProperties}
    >
      <div style={{ position: 'absolute', left: 34, top: 14, width: 96, height: 22, borderRadius: 999, background: 'rgba(0,107,79,0.10)' }} />
      <div style={{ flex: 1, position: 'relative', height: CARD }}>
        <div style={{ ...bar(14, 90, 'bottom'), left: 34 }} />
        <div style={{ ...bar(34, 124, 'bottom'), left: 62 }} />
        <div style={{ ...bar(14, 72, 'bottom'), left: 110 }} />
        <div style={{ ...bar(23, 107, 'bottom'), left: 138 }} />
      </div>
    </div>
  </AbsoluteFill>
);