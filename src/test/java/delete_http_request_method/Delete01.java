package delete_http_request_method;

import base_urls.JsonPlaceHolderBaseUrl;
import io.restassured.response.Response;
import org.junit.Test;

import java.util.HashMap;
import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertEquals;

public class Delete01 extends JsonPlaceHolderBaseUrl {


       /*
        When
	 		I send DELETE Request to the Url https://jsonplaceholder.typicode.com/todos/198
	 	Then
		 	Status code is 200
		 	And Response body is {}
    */

    @Test
    public void delete01(){

        //Set the url
        spec.pathParams("bir","todos", "iki", 198 );

        //Set the expected data
        Map<String, Object> expectedData = new HashMap<>();

        //Send the Delete request and get the response / Delete request gonder ve response elde et
        Response response = given().spec(spec).when().delete("/{bir}/{iki}");

        response.prettyPrint();

        //validate
        response.then().assertThat().statusCode(200);

        Map<String, Object> actualData = response.as(HashMap.class);

        assertEquals(expectedData, actualData);


    }

}
