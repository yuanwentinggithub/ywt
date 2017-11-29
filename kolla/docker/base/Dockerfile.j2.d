FROM {{ base_image }}:{{ base_distro_tag }}
MAINTAINER {{ maintainer }}

{# NOTE(SamYaple): Avoid uid/gid conflicts by creating each user/group up front. #}
{# Specifics required such as homedir or shell are configured within the service specific image #}
{%- for name, user in users | dictsort() %}
{% if loop.first -%}RUN {% else %}    && {% endif -%}
    groupadd --force --gid {{ user.gid }} {{ name }} \
    && useradd -M --shell /usr/sbin/nologin --uid {{ user.uid }} --gid {{ user.gid }} {{ name }}
        {%- if not loop.last %} \{% endif -%}
{%- endfor %}

LABEL kolla_version="{{ kolla_version }}"

{% import "macros.j2" as macros with context %}
{% block base_header %}{% endblock %}

ENV KOLLA_BASE_DISTRO {{ base_distro }}
ENV KOLLA_INSTALL_TYPE {{ install_type }}
ENV KOLLA_INSTALL_METATYPE {{ install_metatype }}

#### Customize PS1 to be used with bash shell
COPY kolla_bashrc /tmp/
RUN cat /tmp/kolla_bashrc >> /etc/skel/.bashrc \
    && cat /tmp/kolla_bashrc >> /root/.bashrc

# PS1 var when used /bin/sh shell
ENV PS1="$(tput bold)($(printenv KOLLA_SERVICE_NAME))$(tput sgr0)[$(id -un)@$(hostname -s) $(pwd)]$ "

{% if base_distro in ['centos', 'oraclelinux', 'rhel'] %}
# For RPM Variants, enable the correct repositories - this should all be done
# in the base image so repos are consistent throughout the system.  This also
# enables to provide repo overrides at a later date in a simple fashion if we
# desire such functionality.  I think we will :)

RUN CURRENT_DISTRO_RELEASE=$(awk '{match($0, /[0-9]+/,version)}END{print version[0]}' /etc/system-release); \
    if [  $CURRENT_DISTRO_RELEASE != "{{ supported_distro_release }}" ]; then \
        echo "Only supported {{ supported_distro_release }} release on {{ base_distro }}"; false; \
    fi \
    && cat /tmp/kolla_bashrc >> /etc/bashrc \
    && sed -i 's|^\(override_install_langs=.*\)|# \1|' /etc/yum.conf

#### BEGIN REPO ENABLEMENT
{% set base_yum_repo_files = [
    'elasticsearch.repo',
    'grafana.repo',
    'influxdb.repo',
    'kibana.yum.repo',
    'MariaDB.repo',
    'td.repo',
    'zookeeper.repo'
 ] %}
{%- for repo_file in base_yum_repo_files | customizable('yum_repo_files') %}
COPY {{ repo_file }} /etc/yum.repos.d/{{ repo_file }}
{%- endfor %}

{% set base_yum_url_packages = [
   'http://repo.percona.com/release/7/RPMS/x86_64/percona-release-0.1-4.noarch.rpm'
] %}
{{ macros.install_packages(base_yum_url_packages | customizable("yum_url_packages")) }}
{% set base_yum_repo_keys = [
    'http://yum.mariadb.org/RPM-GPG-KEY-MariaDB',
    '/etc/pki/rpm-gpg/RPM-GPG-KEY-Percona ',
    'https://packages.elastic.co/GPG-KEY-elasticsearch',
    'https://repos.influxdata.com/influxdb.key',
    'https://packagecloud.io/gpg.key',
    'https://grafanarel.s3.amazonaws.com/RPM-GPG-KEY-grafana',
    'https://packages.treasuredata.com/GPG-KEY-td-agent'
] %}

{%- for key in base_yum_repo_keys | customizable('yum_repo_keys') %}
{%- if loop.first %}RUN {% else %}    && {% endif -%}
    rpm --import {{ key }}
{%- if not loop.last %} \{% endif %}
{% endfor -%}

    {% if install_metatype in ['rdo', 'mixed'] %}

{% for cmd in rpm_setup %}
{{ cmd }}
{% endfor %}

    {% endif %}
    {# endif for repo setup for all RHEL except RHEL OSP #}

    {% if install_metatype == 'rhos' %}

# Turn on the RHOS 7.0 repo for RHOS
RUN yum-config-manager --enable rhel-7-server-rpms \
    && yum-config-manager --enable rhel-7-server-openstack-7.0-rpms

    {% endif %}

    {% if base_distro == 'centos' %}

RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

{% set base_centos_yum_repo_keys = [
    '/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Cloud',
    '/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage',
    '/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Virtualization'
] %}

{% set base_centos_yum_repo_packages = [
    'epel-release ',
    'yum-plugin-priorities',
    'centos-release-ceph-jewel',
    'centos-release-openstack-ocata',
    'centos-release-qemu-ev'
] %}

{{ macros.install_packages(base_centos_yum_repo_packages | customizable("yum_centos_repo_packages")) }}
{% for key in base_centos_yum_repo_keys | customizable('yum_centos_repo_keys') %}
    {%- if loop.first %}RUN {% else %}    && {% endif -%}
    rpm --import {{ key }} \
{% endfor -%}
{%- if base_centos_yum_repo_keys|length ==0 %}RUN {% else %}    && {% endif -%}
    yum clean all

    {% endif %}
    {# Endif for base_distro centos #}

    {% if base_distro == 'rhel' %}

{% block base_rhel_package_installation %}
# Enable couple required repositories for all RHEL builds
# Turn on EPEL throughout the build
RUN yum -y install \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
    && yum-config-manager --enable rhel-7-server-optional-rpms \
    && yum -y install \
           yum-plugin-priorities \
    && yum clean all \
    && yum-config-manager --enable rhel-7-server-extras-rpms
{% endblock %}

    {% endif %}
    {# Endif for base_distro RHEL #}

    {% if base_distro == 'oraclelinux' %}

{% block base_oraclelinux_package_installation %}
COPY oraclelinux-extras.repo /etc/yum.repos.d/oraclelinux-extras.repo
RUN yum -y install \
        tar \
        yum-utils \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
    && rpm -Uvh --nodeps \
        http://mirror.centos.org/centos-7/7/extras/x86_64/Packages/centos-release-openstack-ocata-1-2.el7.noarch.rpm \
        http://mirror.centos.org/centos-7/7/extras/x86_64/Packages/centos-release-ceph-jewel-1.0-1.el7.centos.noarch.rpm \
        http://mirror.centos.org/centos-7/7/extras/x86_64/Packages/centos-release-qemu-ev-1.0-1.el7.noarch.rpm \
        http://mirror.centos.org/centos-7/7/extras/x86_64/Packages/centos-release-virt-common-1-1.el7.centos.noarch.rpm \
        http://mirror.centos.org/centos-7/7/extras/x86_64/Packages/centos-release-storage-common-1-2.el7.centos.noarch.rpm \
    && sed -i 's/\$releasever/7/g' /etc/yum.repos.d/CentOS-*.repo \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Virtualization \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Cloud \
    && yum-config-manager --enable ol7_optional_latest ol7_addons \
    && yum -y install \
           yum-plugin-priorities \
    && yum clean all
{% endblock %}

    {% endif %}
    {# Endif for base_distro oraclelinux #}

#### END REPO ENABLEMENT

{# We are back to the basic if conditional here which is:
    if base_distro in ['centos', 'oraclelinux', 'rhel'] #}
{% block base_redhat_binary_versionlock %}{% endblock %}
    {% if install_type == 'binary' %}
{% set base_centos_binary_packages = [
        'sudo',
        'which',
        'python',
        'lvm2',
        'scsi-target-utils',
        'iproute',
        'iscsi-initiator-utils'
] %}
# Install base packages
{{ macros.install_packages( base_centos_binary_packages | customizable("centos_binary_packages")) }}
    {% endif %}
    {# Endif for install_type binary #}

    {% if install_type == 'source' %}

{% set base_centos_source_packages = [
    'curl',
    'sudo',
    'tar',
    'which',
    'lvm2',
    'scsi-target-utils',
    'iproute',
    'iscsi-initiator-utils'
] %}
# Update packages
{{ macros.install_packages( base_centos_source_packages | customizable("centos_source_packages")) }}

    {% endif %}
    {# endif for install type is source for RPM based distros #}
{# endif for base_distro centos,oraclelinux,rhel #}
{% elif base_distro in ['ubuntu', 'debian'] %}

RUN if [ $(awk -F '=' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release) != "{{ supported_distro_release }}" ]; then \
        echo "Only supported {{ supported_distro_release }} release on {{ base_distro }}"; false; fi

# Customize PS1 bash shell
RUN cat /tmp/kolla_bashrc >> /etc/bash.bashrc

# This will prevent questions from being asked during the install
ENV DEBIAN_FRONTEND noninteractive

# Reducing disk footprint
COPY dpkg_reducing_disk_footprint /etc/dpkg/dpkg.cfg.d/dpkg_reducing_disk_footprint

{% block base_ubuntu_package_pre %}
# Need apt-transport-https and ca-certificates before replacing sources.list or
# apt-get update will not work if any repositories are accessed via HTTPS
RUN apt-get update \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates \
    && apt-get clean
{% endblock %}

{% block base_ubuntu_package_sources_list %}
COPY sources.list.{{ base_distro }} /etc/apt/sources.list
{% endblock %}

{% block base_ubuntu_package_apt_preferences %}
COPY apt_preferences.{{ base_distro }} /etc/apt/preferences
{% endblock %}

{% set base_apt_packages = [
   'apt-utils',
   'curl',
   'gawk',
   'iproute2',
   'kmod',
   'lvm2',
   'open-iscsi',
   'python',
   'sudo',
   'tgt']
%}

{% if base_distro == 'ubuntu' %}
    {# 05CE15085FC09D18E99EFB22684A14CF2582E0C5 -- InfluxDB Packaging Service <support@influxdb.com> #}
    {# 177F4010FE56CA3336300305F1656F24C74CD1D8 -- MariaDB Signing Key <signing-key@mariadb.org> #}
    {# 391A9AA2147192839E9DB0315EDB1B62EC4926EA -- Canonical Cloud Archive Signing Key <ftpmaster@canonical.com> #}
    {# 418A7F2FB0E1E6E7EABF6FE8C2E73424D59097AB -- packagecloud ops (production key) <ops@packagecloud.io> #}
    {# 46095ACC8548582C1A2699A9D27D666CD88E42B4 -- Elasticsearch (Elasticsearch Signing Key) <dev_ops@elasticsearch.org> #}
    {# 4D1BB29D63D98E422B2113B19334A25F8507EFA5 -- Percona MySQL Development Team (Packaging key) <mysql-dev@percona.com> #}
    {# 58118E89F3A912897C070ADBF76221572C52609D -- Docker Release Tool (releasedocker) <docker@docker.com> #}
    {# 901F9177AB97ACBE                         -- Treasure Data, Inc (Treasure Agent Official Signing key) <support@treasure-data.com> #}
    {% set base_apt_keys = [
      '05CE15085FC09D18E99EFB22684A14CF2582E0C5',
      '177F4010FE56CA3336300305F1656F24C74CD1D8',
      '391A9AA2147192839E9DB0315EDB1B62EC4926EA',
      '418A7F2FB0E1E6E7EABF6FE8C2E73424D59097AB',
      '46095ACC8548582C1A2699A9D27D666CD88E42B4',
      '4D1BB29D63D98E422B2113B19334A25F8507EFA5',
      '58118E89F3A912897C070ADBF76221572C52609D',
      '901F9177AB97ACBE',
    ] %}
{% elif base_distro == 'debian' %}
    {% set base_apt_keys = [
      '58118E89F3A912897C070ADBF76221572C52609D',
      '0xcbcb082a1bb943db',
      'D27D666CD88E42B4',
      '05CE15085FC09D18E99EFB22684A14CF2582E0C5',
      '418A7F2FB0E1E6E7EABF6FE8C2E73424D59097AB',
      '901F9177AB97ACBE',
    ] %}
    {% set base_apt_packages = base_apt_packages +
      ['sudo',]
    %}
{% endif %}

{% block base_ubuntu_package_installation %}
    {%- block base_ubuntu_package_key_installation %}
        {%- for key in base_apt_keys | customizable('apt_keys') %}
            {%- if loop.first %}RUN {% else %} && {% endif %}apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 {{ key }}
            {%- if not loop.last %} \
            {% endif -%}
        {% endfor %}
    {% endblock %}
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get -y dist-upgrade \
    && apt-get -y install --no-install-recommends \
    {%- for package in base_apt_packages | customizable('apt_packages') %}
        {{ package }} \
    {%- endfor %}
    && apt-get clean
{% endblock %}

{% if base_distro == 'ubuntu' %}
RUN sed -i \
        -e "s|\('purelib': '\$base/\)local/\(lib/python\$py_version_short/dist-packages',\)|\1\2|" \
        -e "s|\('platlib': '\$platbase/\)local/\(lib/python\$py_version_short/dist-packages',\)|\1\2|" \
        -e "s|\('headers': '\$base/\)local/\(include/python\$py_version_short/\$dist_name',\)|\1\2|" \
        -e "s|\('scripts': '\$base/\)local/\(bin',\)|\1\2|" \
        -e "s|\('data'   : '\$base\)/local\(',\)|\1\2|" \
        /usr/lib/python2.7/distutils/command/install.py \
    && rm -rf /usr/lib/python2.7/site-packages \
    && ln -s dist-packages /usr/lib/python2.7/site-packages
{% endif %}

{# endif for base_distro ubuntu, debian #}
{% endif %}

COPY set_configs.py /usr/local/bin/kolla_set_configs
COPY start.sh /usr/local/bin/kolla_start
COPY sudoers /etc/sudoers
COPY curlrc /root/.curlrc
COPY aliyun_ocata.repo /etc/yum.repos.d/aliyun_ocata.repo

{% block dumb_init_installation %}
RUN curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.1.3/dumb-init_1.1.3_amd64 -o /usr/local/bin/dumb-init \
    && chmod +x /usr/local/bin/dumb-init
{% endblock %}

RUN touch /usr/local/bin/kolla_extend_start \
    && chmod 755 /usr/local/bin/kolla_start /usr/local/bin/kolla_extend_start /usr/local/bin/kolla_set_configs \
    && chmod 440 /etc/sudoers \
    && mkdir -p /var/log/kolla \
    && chown :kolla /var/log/kolla \
    && chmod 2775 /var/log/kolla \
    && rm -f /tmp/kolla_bashrc

{% block base_footer %}{% endblock %}
CMD ["kolla_start"]
