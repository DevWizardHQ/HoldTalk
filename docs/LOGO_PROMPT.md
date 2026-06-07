# Logo Generation Prompt

A placeholder vector logo lives at [`assets/logo.svg`](../assets/logo.svg).
For a polished AI-generated logo, paste the prompt below into an image model
(Midjourney, DALL·E, Ideogram, Recraft, etc.).

## Primary prompt

> Minimal modern app icon for "WizFlow", a macOS voice dictation tool.
> A sleek white microphone on the left morphing into smooth flowing sound
> waves that transform into lines of text on the right, symbolizing speech
> becoming writing. Vibrant gradient background from deep indigo (#4F46E5)
> through violet (#7C3AED) to cyan (#06B6D4). Rounded-square macOS Big Sur
> style app icon shape with subtle depth and soft inner shadow. Flat vector
> style, crisp edges, no text, no letters, centered composition, high
> contrast, professional, suitable for a 1024x1024 app icon.

## Variations to try

- **Glassmorphism**: append — "frosted glass effect, translucent layers, soft glow"
- **Dark mode**: replace gradient with "near-black background (#0B1120) and a glowing cyan-violet waveform"
- **Wordmark** (for README header): "horizontal logo, the flowing waveform mark on the left, generous negative space on the right for a wordmark, transparent background"

## Converting to a macOS app icon

```bash
# Render PNG sizes from your final 1024px image, then:
mkdir AppIcon.iconset
for s in 16 32 64 128 256 512; do
  sips -z $s $s icon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) icon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
# Then copy AppIcon.icns into dist/WizFlow.app/Contents/Resources/
# and add CFBundleIconFile = AppIcon to Resources/Info.plist
```
