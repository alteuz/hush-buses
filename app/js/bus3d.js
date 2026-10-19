// Low-poly 3D bus (Three.js) rendered off-screen and painted into each map
// marker's <canvas>. One WebGL context is shared by every bus on the map.
window.Bus3D = (function () {
  const PX = 128;                       // render size (drawn at 64 css px → retina-sharp)
  let renderer = null, scene, camera, bus;
  let ok = false;

  function mat(color, extra) {
    return new THREE.MeshLambertMaterial(Object.assign({ color: color }, extra || {}));
  }

  function box(w, h, l, material, x, y, z) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, l), material);
    m.position.set(x || 0, y || 0, z || 0);
    return m;
  }

  // Model faces -Z (north on the map). Units ≈ metres / 4.
  function buildBus() {
    const g = new THREE.Group();
    const magenta = mat(0xff2d9b);
    const shell = mat(0xf1e2ee);
    const glass = mat(0x1a1220);
    const lav = mat(0xb98cf0);
    const tire = mat(0x16101b);

    g.add(box(1.0, 0.46, 2.7, magenta, 0, 0.34, 0));          // lower body (Hush livery)
    g.add(box(1.0, 0.40, 2.7, shell, 0, 0.77, 0));            // upper body
    g.add(box(1.0, 0.07, 2.7, lav, 0, 0.58, 0));              // lavender stripe
    g.add(box(1.02, 0.25, 2.2, glass, 0, 0.79, 0.12));        // side windows
    g.add(box(0.88, 0.30, 0.03, glass, 0, 0.77, -1.36));      // windshield
    g.add(box(0.80, 0.22, 0.03, glass, 0, 0.80, 1.36));       // rear window
    g.add(box(0.98, 0.06, 2.6, mat(0xd9c3e8), 0, 1.0, 0));    // roof
    g.add(box(0.60, 0.10, 0.80, lav, 0, 1.08, 0.3));          // A/C unit
    g.add(box(0.56, 0.08, 0.03, mat(0x36d6b0, { emissive: 0x36d6b0 }), 0, 0.96, -1.37)); // LED destination sign

    const head = mat(0xfff6c8, { emissive: 0xfff2b0 });
    g.add(box(0.16, 0.08, 0.03, head, -0.36, 0.28, -1.36));
    g.add(box(0.16, 0.08, 0.03, head, 0.36, 0.28, -1.36));
    const tail = mat(0xff3355, { emissive: 0xaa0022 });
    g.add(box(0.14, 0.12, 0.03, tail, -0.38, 0.32, 1.36));
    g.add(box(0.14, 0.12, 0.03, tail, 0.38, 0.32, 1.36));

    const wheelGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.14, 18);
    [[-0.5, -0.9], [0.5, -0.9], [-0.5, 0.88], [0.5, 0.88]].forEach(function (p) {
      const w = new THREE.Mesh(wheelGeo, tire);
      w.rotation.z = Math.PI / 2;
      w.position.set(p[0], 0.2, p[1]);
      g.add(w);
    });

    // soft contact shadow
    const shadow = new THREE.Mesh(
      new THREE.CircleGeometry(1, 32),
      new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.35 })
    );
    shadow.rotation.x = -Math.PI / 2;
    shadow.scale.set(0.75, 1.55, 1);
    shadow.position.y = 0.01;
    g.add(shadow);
    return g;
  }

  function init() {
    if (renderer || !window.THREE) return ok;
    try {
      renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
      renderer.setPixelRatio(1);
      renderer.setSize(PX, PX, false);
      renderer.setClearColor(0x000000, 0);

      scene = new THREE.Scene();
      scene.add(new THREE.HemisphereLight(0xffffff, 0x3a2140, 0.8));
      const sun = new THREE.DirectionalLight(0xffffff, 0.75);
      sun.position.set(3, 8, 4);
      scene.add(sun);

      // north-up map seen from the south at ~58°
      const f = 1.55;
      camera = new THREE.OrthographicCamera(-f, f, f, -f, 0.1, 50);
      camera.position.set(0, 8, 5);
      camera.lookAt(0, 0.3, 0);

      bus = buildBus();
      scene.add(bus);
      ok = true;
    } catch (e) {
      ok = false;
    }
    return ok;
  }

  // heading: degrees clockwise from north (0 = north, 90 = east)
  function render(canvas, heading) {
    if (!init()) return false;
    bus.rotation.y = -heading * Math.PI / 180;
    renderer.render(scene, camera);
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(renderer.domElement, 0, 0, canvas.width, canvas.height);
    return true;
  }

  return { render: render, available: function () { return init(); }, size: PX };
})();
