<AutoPilot:project xmlns:AutoPilot="com.autoesl.autopilot.project" top="fft_psd" name="fft_psd_proj" ideType="classic">
    <files>
        <file name="src/fft_psd.cpp" sc="0" tb="false" cflags="" csimflags="" blackbox="false"/>
        <file name="../../tb/tb_fft_psd.cpp" sc="0" tb="1" cflags="-I../../src -Wno-unknown-pragmas" csimflags="" blackbox="false"/>
    </files>
    <solutions>
        <solution name="sol1" status=""/>
    </solutions>
    <Simulation argv="">
        <SimFlow name="csim" setup="false" optimizeCompile="false" clean="false" ldflags="" mflags=""/>
    </Simulation>
</AutoPilot:project>
