import React from 'react';
import {
  AbsoluteFill,
  staticFile,
  useVideoConfig,
} from 'remotion';
import { brandColor, brandColorDark, type CanvasSize, type Screen } from './screens';

const SCREEN_ASPECT = 2400 / 1080;

const layouts: Record<
  CanvasSize,
  { deviceWidth: number; bottom: number; headerBottom: number; logo: number; titleFont: number; taglineFont: number }
> = {
  phone: { deviceWidth: 640, bottom: 128, headerBottom: 238, logo: 76, titleFont: 86, taglineFont: 36 },
  tall: { deviceWidth: 840, bottom: 96, headerBottom: 292, logo: 88, titleFont: 104, taglineFont: 40 },
};

const BEZEL_TOP = 46;
const BEZEL_BOTTOM = 18;
const BEZEL_SIDE = 20;
const DEVICE_RADIUS = 44;
const SCREEN_RADIUS = 30;

export const PlayFrame: React.FC<{
  screen: Screen;
  size: CanvasSize;
}> = ({ screen, size }) => {
  const { width, height } = useVideoConfig();
  const L = layouts[size];

  const displayHeight = L.deviceWidth * SCREEN_ASPECT;
  const bezelWidth = L.deviceWidth + BEZEL_SIDE * 2;
  const bezelHeight = displayHeight + BEZEL_TOP + BEZEL_BOTTOM;
  const deviceLeft = (width - bezelWidth) / 2;
  const deviceTop = height - bezelHeight - L.bottom;
  const screenLeft = deviceLeft + BEZEL_SIDE;
  const screenTop = deviceTop + BEZEL_TOP;

  const buttonTop = deviceTop + bezelHeight * 0.28;
  const buttonHeight = bezelHeight * 0.14;
  const buttonWidth = 9;

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(165deg, ${brandColorDark} 0%, #0A5F43 48%, #0E8B5C 100%)`,
        fontFamily: '"Segoe UI", system-ui, Arial, sans-serif',
      }}
    >
      <AbsoluteFill
        style={{
          background:
            'radial-gradient(1200px 700px at 50% -10%, rgba(255,255,255,0.16), rgba(255,255,255,0) 60%)',
        }}
      />

      {/* Cabecera */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 96,
          right: 96,
          height: L.headerBottom,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'flex-end',
          paddingBottom: 26,
        }}
      >
        <div
          style={{
            width: L.logo,
            height: L.logo,
            borderRadius: (L.logo * 26) / 76,
            background: '#FFFFFF',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 5,
            marginBottom: 14,
          }}
        >
          <div style={{ width: 5, height: L.logo * 0.42, background: brandColor, borderRadius: 3 }} />
          <div style={{ width: 12, height: L.logo * 0.58, background: brandColor, borderRadius: 3 }} />
          <div style={{ width: 5, height: L.logo * 0.34, background: brandColor, borderRadius: 3 }} />
          <div style={{ width: 8, height: L.logo * 0.5, background: brandColor, borderRadius: 3 }} />
        </div>

        <div
          style={{
            color: '#FFFFFF',
            fontSize: L.titleFont,
            fontWeight: 800,
            letterSpacing: -1.5,
            lineHeight: 1.04,
            textAlign: 'center',
            whiteSpace: 'nowrap',
          }}
        >
          {screen.title}
        </div>

        <div
          style={{
            color: 'rgba(255,255,255,0.82)',
            fontSize: L.taglineFont,
            fontWeight: 500,
            textAlign: 'center',
            marginTop: 10,
            maxWidth: width - 240,
          }}
        >
          {screen.tagline}
        </div>
      </div>

      {/* Botones laterales */}
      <div
        style={{
          position: 'absolute',
          left: deviceLeft - buttonWidth - 3,
          top: buttonTop,
          width: buttonWidth,
          height: buttonHeight,
          background: '#0E1116',
          borderRadius: 5,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: deviceLeft + bezelWidth + 3,
          top: buttonTop + 40,
          width: buttonWidth,
          height: buttonHeight * 0.7,
          background: '#0E1116',
          borderRadius: 5,
        }}
      />

      {/* Marco del teléfono */}
      <div
        style={{
          position: 'absolute',
          left: deviceLeft,
          top: deviceTop,
          width: bezelWidth,
          height: bezelHeight,
          borderRadius: DEVICE_RADIUS,
          background: '#0B0D12',
          boxShadow: '0 60px 120px rgba(0,0,0,0.45)',
          overflow: 'hidden',
        }}
      >
        {/* Pantalla */}
        <div
          style={{
            position: 'absolute',
            left: BEZEL_SIDE,
            top: BEZEL_TOP,
            width: L.deviceWidth,
            height: displayHeight,
            borderRadius: SCREEN_RADIUS,
            overflow: 'hidden',
            background: '#000',
          }}
        >
          <img
            src={staticFile(screen.image)}
            width={L.deviceWidth}
            height={displayHeight}
            style={{ objectFit: 'cover', display: 'block' }}
          />
          {/* Punch-hole Pixel */}
          <div
            style={{
              position: 'absolute',
              top: 22,
              left: L.deviceWidth / 2 - 9.5,
              width: 19,
              height: 19,
              borderRadius: 10,
              background: '#0B0D12',
              border: '2px solid rgba(255,255,255,0.35)',
            }}
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};