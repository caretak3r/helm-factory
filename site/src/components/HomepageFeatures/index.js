import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Capability Gates',
    Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
    description: (
      <>
        Every generator negotiates the best <code>apiVersion</code> the target
        cluster actually serves and silently skips CRD-backed objects whose API
        is absent, so a rendered chart never conflicts on deploy.
      </>
    ),
  },
  {
    title: 'Comprehensive Coverage',
    Svg: require('@site/static/img/undraw_docusaurus_tree.svg').default,
    description: (
      <>
        Beyond the opinionated primary-app objects, <code>extraObjects</code>{' '}
        renders any Kubernetes Kind through one capability-gated generic
        renderer, and <code>extraManifests</code> is a raw escape hatch.
      </>
    ),
  },
  {
    title: 'Secure by Default',
    Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
    description: (
      <>
        PSS-restricted target, pinned images, dedicated service accounts, and
        fail-closed mTLS — the zero-config posture is the secure posture.
      </>
    ),
  },
];

function Feature({Svg, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
