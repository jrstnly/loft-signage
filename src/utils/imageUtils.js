// Utility functions for image handling

export const loadImage = (src) => {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
};

export const getImagePlaceholder = () => {
  return {
    src: null,
    alt: 'Upload your 16:9 image here',
    recommendedSize: '3840x2160px for 4K displays'
  };
};

export const validateImageAspectRatio = (width, height) => {
  const aspectRatio = width / height;
  const targetRatio = 16 / 9;
  const tolerance = 0.1; // Allow some tolerance
  
  return Math.abs(aspectRatio - targetRatio) <= tolerance;
};

export const getOptimalImageSize = (displayWidth, displayHeight) => {
  // For 4K displays, recommend 3840x2160
  // For smaller displays, scale proportionally
  const maxWidth = Math.min(displayWidth, 3840);
  const maxHeight = Math.min(displayHeight * 0.36, 2160); // 36% of screen height
  
  return {
    width: maxWidth,
    height: maxHeight
  };
};
