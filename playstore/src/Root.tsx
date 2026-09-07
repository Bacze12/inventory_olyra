import React from 'react';
import { Composition } from 'remotion';
import { PlayFrame } from './PlayFrame';
import { PlayBanner } from './PlayBanner';
import { Icon512 } from './Icon512';
import { canvasSizes, screens } from './screens';

const fps = 30;

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="icon-512x512"
      component={Icon512}
      durationInFrames={fps}
      fps={fps}
      width={512}
      height={512}
    />
    <Composition
      id="featured-1024x500"
      component={PlayBanner}
      durationInFrames={fps}
      fps={fps}
      width={1024}
      height={500}
    />
    {screens.map((screen) =>
      canvasSizes.map((canvas) => {
        const id = `${screen.id}-${canvas.width}x${canvas.height}`;
        return (
          <Composition
            key={id}
            id={id}
            component={PlayFrame}
            durationInFrames={fps}
            fps={fps}
            width={canvas.width}
            height={canvas.height}
            defaultProps={{ screen, size: canvas.id }}
          />
        );
      }),
    )}
  </>
);